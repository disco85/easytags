(in-package "EASYTAGS")

(defun dbg (s x) (format t "*** TRACE[~A]: ~S~%" s x) x)

(defun nully (x)
  "If `x` looks as empty string/list/0/0.0 then nil is returned, else `x`"
  ;; typecase bcs SBCL reports type-errors (x is treated in the same expr as having diff types)
  (typecase x
    (null nil)
    (string (if (string= "" x) nil x))
    (number (if (= 0 x) nil x))
    (t x)))


(defun last-path-component (path &key and-type)
  "Returns c for /a/b/c/ or /a/b/c.txt. With `and-type` - c.txt for the second"
  (let* ((pn (pathname path)))
    (or (nully (if and-type (file-namestring pn) (pathname-name pn)))
        (car (last (pathname-directory pn))))))


(defun add-last (list el)
  (append list (list el)))


(defun add-nth (list el n)
  (append (subseq list 0 n)
          (list el)
          (subseq list n)))


(defun create-link (src-path link-path)
  "Creates symbolic/soft link"
  (ecase *OS*
    (:windows (uiop:run-program `("mklink" "/D" ,link-path ,src-path))) ; BUG? /D for dirs
    (:unix (uiop:run-program `("ln" "-s" ,src-path ,link-path)))
    (:mac (uiop:run-program `("ln" "-s" ,src-path ,link-path)))))


(defun resolve-path (path)
  "Resolves .. in a path"
  (let ((parsed-path
          ;; adds CWD to pathname structure (without to resolve it)
          (uiop:merge-pathnames* (if (equal *OS* :windows)
                                     (uiop:parse-native-namestring path)
                                     (uiop:parse-unix-namestring path)))))
    (uiop:resolve-symlinks (uiop:ensure-absolute-pathname parsed-path))))


(defun is-color-term-available ()
  (cond
    ((not (interactive-stream-p *standard-output*)) nil)
    ((not (equal *OS* :windows)) t)
    (t nil)))


(defun can-i-colorize (outfmt all-tags-selected &optional colorless)
  (ecase colorless
    (1 t)
    (0 nil)
    (2 (and (is-color-term-available) (getf +outfmt-color+ outfmt)
            (not all-tags-selected)))))


(defun ansi-color-code (color &optional bg)
  "Returns ANSI color code for foreground or background if `bg` is set"
  (let* ((pos (position color '(:black :red :green :yellow :blue :magenta :cyan :white)))
         (code (when pos (if bg (+ pos 40) (+ pos 30)))))
    code))


(defun ansi-attr-code (attr-name)
  (case attr-name
    (:bold 1)
    (:italic 3)
    (:underline 4)
    (:reverse 7)))


(defun ansi-colorize (text &key fg bg bold italic underline reverse)
  (let ((attrs (remove nil
                       (list (ansi-color-code fg)
                             (ansi-color-code bg t)
                             (ansi-attr-code (when bold :bold))
                             (ansi-attr-code (when italic :italic))
                             (ansi-attr-code (when underline :underline))
                             (ansi-attr-code (when reverse :reverse))))))
    (format nil "~c[~{~A~^;~}m~A~c[0m" #\ESC attrs text #\ESC)))


(defun maybe-dir-p (p)
  "Checks if path `p` is a directory. Does not work on Mac and maybe on Windows"
  (probe-file (concatenate 'string (namestring p) "/.")))  ;; FIXME not portable /


(defun replace-all (repl-pairs in-str)
  "Replaces in-str all pairs like '((from . to) (from . to) ...)"
  (reduce (lambda (s pair)
            (ppcre:regex-replace-all (car pair) s (cdr pair)))
          repl-pairs
          :initial-value in-str))
;; (defun repl (repl-pairs in-str)
;;   (loop :with s = in-str
;;         :for (this . by-this) :in repl-pairs
;;         :do (setf s (ppcre:regex-replace this s by-this))
;;         :finally (return s)))

(defun insert-or-combine (ht key new-value &key combine)
  (let ((old-value (gethash key ht nil)))
    (setf (gethash key ht)
          (if old-value
              (funcall (or combine (constantly new-value)) old-value new-value)
              new-value))))



(defun url-encode-rfc3986 (input &optional safe-chars)
  "Percent-encodes INPUT string according to RFC 3986 using only standard Common Lisp."
  (labels ((unreserved-char-p (ch)
             (or (and (char>= ch #\A) (char<= ch #\Z))
                 (and (char>= ch #\a) (char<= ch #\z))
                 (and (char>= ch #\0) (char<= ch #\9))
                 (member ch '(#\- #\_ #\. #\~))
                 (member ch (coerce safe-chars 'list))))
           (encode-byte (byte stream)
             (format stream "%~2,'0X" byte))
           ;; Manual UTF-8 encoding for a single character
           (utf8-bytes (ch)
             (let ((code (char-code ch)))
               (cond
                 ((<= code #x7F)
                  (list code))
                 ((<= code #x7FF)
                  (list (+ #xC0 (ash code -6))
                        (+ #x80 (logand code #x3F))))
                 ((<= code #xFFFF)
                  (list (+ #xE0 (ash code -12))
                        (+ #x80 (logand (ash code -6) #x3F))
                        (+ #x80 (logand code #x3F))))
                 ((<= code #x10FFFF)
                  (list (+ #xF0 (ash code -18))
                        (+ #x80 (logand (ash code -12) #x3F))
                        (+ #x80 (logand (ash code -6) #x3F))
                        (+ #x80 (logand code #x3F))))
                 (t
                  (error "Invalid Unicode character: ~A" ch))))))
    (with-output-to-string (out)
      (loop :for ch :across input :do
           (if (unreserved-char-p ch)
               (write-char ch out)
               (loop :for byte :in (utf8-bytes ch) :do
                    (encode-byte byte out)))))))
