(in-package :easytags)

;;; Variables
;; 1. dirs must ends with / (in CL it's dir!)
;; 2. All platform/OS/installation specific variables are defined as
;;    mutable variables (with `defparameter`) and they are defined at
;;    rune-time (see `main`) so their values will be relevant to the
;;    environment when we run. Else, with binary built by `ros build ...`
;;    we get a binary with hardcoded (but not seen with `strings`!!!)
;;    variables from the build PC box!

(defparameter *tags-dir* nil)

(defun det-*tags-dir* ()
  (uiop:if-let ((env-tags-dir (uiop:getenv "EASYTAG_HOME")))
               (uiop:ensure-directory-pathname (uiop:native-namestring env-tags-dir))
               (uiop:native-namestring
                (merge-pathnames ".tags/" (user-homedir-pathname)))))


;; Current OS
(defparameter *OS* nil)


;; Name (path) of the script
(defparameter *SCRIPT-NAME* nil)


(defun det-*OS* ()
  (cond ((member :windows *features*) :windows)
        ((member :unix *features*)
         (cond ((member :darwin *features*) :mac)
               (t :unix)))
        (t (error "OS not recognized!"))))


;; Path separator (as a string)
(defparameter *path-sep* nil)

(defun det-*path-sep* ()
  (ecase *OS* (:windows "\\") (:unix "/") (:mac "/")))


;; Supported output formats
(defparameter +outfmt+ '(:report :grep :emacs :xcons :cd :src))

(defparameter +outfmt-color+ '(:report t :grep t :emacs nil :xcons t :cd t :src nil))

;; The length of horizontal line (hline)
(defparameter +hline-len+ 60)

;; Supported shells autocomplete
(defparameter +ac-shell+ '(:bash :zsh))

;; How to output matched part of a tag
(defparameter +matched-ansi-attrs+ '(:fg :red :bold t))

;; How to output files of a matched tag
(defparameter +file-ansi-attrs+ '(:fg :magenta))

(defparameter +bool-enum-opt+ '(("y" . 1) ("n" . 0) ("yes" . 1) ("no" . 0)
                                ("1" . 1) ("0" . 0) ("true" . 1) ("false" . 0)
                                ("on" . 1) ("off" . 0) ("-" . 2)))


(defun tag-fs-object (path tags)
  "Tags FS-object"
  (let* ((path-1 (resolve-path path))
         (name (last-path-component path-1))
         (abs-path (truename path-1))
         (uniq-part (format nil "~X" (sxhash abs-path)))
         (tag-dirname (format nil "~A-~A/" name uniq-part))  ;; .../ even for Win
         (tag-dir (merge-pathnames tag-dirname *tags-dir*))
         (tags-file (merge-pathnames #p"tags" tag-dir))
         (link-file (merge-pathnames #p"link" tag-dir))
         (new (nth-value 1 (ensure-directories-exist tag-dir))))
    (if new
        (prog1
            (with-open-file (f tags-file :direction :output)
              (write-string (format nil "src!~A~%~{user!~A~%~}" abs-path tags) f))
          (create-link (namestring abs-path) (namestring link-file))
          (format t "Object ~A tagged in ~A~%" abs-path tags-file))
        (with-open-file (f tags-file :direction :output
                                     :if-exists :append
                                     :if-does-not-exist :create)
          (write-string (format nil "~{user!~A~%~}" tags) f)
          (format t "Object ~A additionally tagged in ~A~%" abs-path tags-file)))))


(defstruct (matched
            (:print-object
             (lambda (me stream)
              (if (and (matched-colored me) (matched-outfmt me) (matched-beg me))
                  (format stream "~A"
                          (concatenate
                           'string
                           (subseq (matched-str me) 0 (matched-beg me))
                           (apply #'ansi-colorize
                                  (subseq (matched-str me) (matched-beg me) (matched-end me))
                                  +matched-ansi-attrs+)
                           (subseq (matched-str me) (or (matched-end me) (length (matched-str me))))))
                  (format stream "~A" (matched-str me))))))
  str beg end outfmt colored)



(defun select-tags-file (file &optional file-rexpr)
  "Selects tags-file inside tag directory"
  (format t "SELECT-TAGS-FILE: file=~A  file-rexpr=~A~%" file file-rexpr)
  (and (ppcre:scan "[/\]tags[/\]?$" file)
       (if file-rexpr (ppcre:scan file-rexpr file) t)))


(defun match-tags (tagfile tag-rexpr outfmt colorless)
  (let* ((tag-rexpr-1 (or tag-rexpr ".*"))
         (all-tags-selected (null tag-rexpr))
         (matched-tags nil)
         (src-tag nil))
    (setf
     matched-tags
     (loop :for line :in (uiop:read-file-lines tagfile)
           :for scanned = (multiple-value-list (ppcre:scan tag-rexpr-1 line))
           :for is-src-tag = (multiple-value-list (ppcre:scan "^src!" line))
           :when (car is-src-tag)
             :do (setf src-tag (subseq line (length "src!")))
           :when (car scanned)
             :append (list (make-matched :str line
                                         :beg (nth 0 scanned)
                                         :end (nth 1 scanned)
                                         :colored (can-i-colorize
                                                   outfmt
                                                   all-tags-selected colorless)
                                         :outfmt outfmt))))
    (when matched-tags (list src-tag matched-tags))))


(defun tagfiles-iter (matched-tagfile-fsm tag-rexpr outfmt colorless &optional file-rexpr)
  (let* ((match-tags-1
           (lambda (tagfile) (and (select-tags-file (namestring tagfile) file-rexpr)
                                  (funcall #'match-tags tagfile tag-rexpr outfmt colorless)))))
    (loop :for tagdir :in (uiop:subdirectories *tags-dir*)
          :do (loop :for tagfile :in (uiop:directory-files tagdir)
                    :for matched-tags = (funcall match-tags-1 tagfile)
                    :when matched-tags
                      :do (funcall matched-tagfile-fsm (cons tagfile matched-tags)))))
  (funcall matched-tagfile-fsm :end!)) ;; tagfile src-tag [matched-tags]+



;; (declaim (ftype (function () t) cli-simple-quote))
(defun cli-simple-quote (s)
  (case *OS*
    (:windows (concatenate 'string "\"" s "\""))
    (t (concatenate 'string "'" s "'"))))


(defun find-tag (tag-rexpr outfmt colorless &optional file-rexpr)
  (let*
      ((all-tags-selected (null tag-rexpr))

       (out-header (lambda ()
                     (case outfmt
                       (:emacs (format t "# -*- mode: org; -*-~%")))))

       (out-footer (lambda () nil))

       (hline (format nil "~v@{~A~:*~}~%" +hline-len+ "-"))

       (get-srcdir (lambda (el)
                     "For dir it returns the dir itself"
                     (namestring (make-pathname :directory
                                                (pathname-directory (nth 1 el))))))

       (safe-url-chars "/")

       (out-el (lambda (el)
                 (ecase outfmt
                   (:grep (destructuring-bind (tagfile srcfile matched-tags) el
                            (declare (ignorable tagfile))
                            (loop
                              :for matched-tag :in matched-tags
                              :when (not (eql 0 (search "src!" (matched-str matched-tag))))
                                :do
                                   (format t "~A:~A~%"
                                           (if (can-i-colorize outfmt all-tags-selected colorless)
                                               (apply #'ansi-colorize srcfile +file-ansi-attrs+)
                                               srcfile)
                                           matched-tag))))
                   (:cd (format t "cd ~A~%" (cli-simple-quote (funcall get-srcdir el))))
                   (:report (apply #'format t "Tags: ~A~%~*~{~A~%~}~A~%" (add-last el hline)))
                   (:src (format t "~A~%" (nth 1 el)))
                   (:xcons
                    (let ((el-1 (add-nth (add-last el hline) (funcall get-srcdir el) 2)))
                      (setf (nth 0 el-1) (url-encode-rfc3986 (namestring (nth 0 el-1)) safe-url-chars)
                            (nth 1 el-1) (url-encode-rfc3986 (namestring (nth 1 el-1)) safe-url-chars)
                            (nth 2 el-1) (url-encode-rfc3986 (namestring (nth 2 el-1)) safe-url-chars))
                      (apply
                       #'format
                       t
                       "[Tags] file://~A~%[ Src] file://~A~%[ Dir] file://~A~%~{~A~%~}~A~%"
                       el-1)))
                   (:emacs
                    (let ((el-1 (destructuring-bind (tagfile srcfile matched-tags) el
                                  (list
                                   (last-path-component srcfile :and-type t)
                                   tagfile
                                   srcfile
                                   (if (maybe-dir-p srcfile) "directory" "file")
                                   matched-tags
                                   hline))))
                      (apply
                       #'format
                       t
                       "* ~A~%~%** Files~%~%[[~A][Tags file]]~%~%[[~A][SRC ~A]]~%~%** Tags~%~%~{- ~A~%~}~%~A~%"
                       el-1))))))

       ;; FSM related (st-*):
       (st :beg)

       (st-el nil)

       (fsm (lambda (ev)
              (case st
                (:beg (case ev
                        (:end!
                         (setf st :end))
                        (t
                         (setf st :sol)
                         (setf st-el ev))))
                (:sol (case ev
                        (:end!
                         (funcall out-header)
                         (funcall out-el st-el)
                         (funcall out-footer)
                         (setf st :end))
                        (t
                         (funcall out-header)
                         (funcall out-el st-el)
                         (setf st :mul)
                         (setf st-el ev))))
                (:mul (case ev
                        (:end!
                         (funcall out-el st-el)
                         (funcall out-footer)
                         (setf st :end))
                        (t
                         (funcall out-el st-el)
                         (setf st-el ev))))
                (:end nil))))) ;; end of fsm

    (tagfiles-iter fsm tag-rexpr outfmt colorless file-rexpr)))

(defun match-file-lines (input-path rexpr)
  "Returns T if any line inside a file INPUT-PATH matches REXPR regexp, else NIL"
  (with-open-file (in input-path :direction :input)
    (loop for line = (read-line in nil nil)
          while line
          thereis (ppcre:scan rexpr line))))


(defun filter-file-lines (input-path output-path tag-rexprs)
  "Removes lines from a file INPUT-FILE matching some of regexp in the list TAG-REXEPRS.
These regexps can be even 'src!.*' but such lines are protected: if a line is '^src!.*'
- it is kept as is"
  (with-open-file (in input-path :direction :input)
    (with-open-file (out output-path
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (loop for line = (read-line in nil nil)
            while line do
              (when
                  (or (ppcre:scan "^src!" line)
                      (not (some
                            #'(lambda (tag-rexpr) (ppcre:scan tag-rexpr line))
                            tag-rexprs)))
                (write-line line out))))))

(defun temp-file-path ()
  (merge-pathnames
   (make-pathname :name (format nil "easytags-filter-~A" (gensym))
                  :type "tmp")
   (uiop:temporary-directory)))

(defun filter-file-lines-in-place (path tag-rexprs)
  "Like FILTER-FILE-LINES but does it in place (with the same file)"
  (when (probe-file path)
    (let ((temp-path (temp-file-path)))
      (unwind-protect
           (progn
             (filter-file-lines path temp-path tag-rexprs)
             (uiop:copy-file temp-path path)
             (delete-file temp-path))
        ;; cleanup in case something fails
        (when (probe-file temp-path)
          (delete-file temp-path))))))

(defun remove-tag (tag-rexprs &optional file-rexpr)
  (loop :for tagdir :in (uiop:subdirectories *tags-dir*)
        :do (loop :for tagfile :in (uiop:directory-files tagdir)
                  :for matched-tagfile = (match-file-lines (namestring tagfile) file-rexpr)
                  :when matched-tagfile
                    :do ;;(format t "!!!MATCHED: ~A~%" tagfile)
                        (filter-file-lines-in-place tagfile tag-rexprs))))


;;; CLI options
(defun cli-kw-getopt (cmd key)
  "Allows to get a choice/enum option as a symbol in :keyword package ready for eq/getf/..."
  (intern (string-upcase (clingon:getopt cmd key)) :keyword))


(defun cli-tag-cmd-handler (cmd)
  (destructuring-bind (path &rest tags) (clingon:command-arguments cmd)
    (let* ((remove (clingon:getopt cmd :remove))
           (move (clingon:getopt cmd :move)))
      (cond
        (remove (remove-tag tags path)) ;; -r,--remove is higher priority
        (move (remove-tag tags ".*")
              (tag-fs-object path tags))
        (t (tag-fs-object path tags))))))


(defun cli-tagged-cmd-handler (cmd)
  (destructuring-bind (&optional tag-rexpr file-rexpr) (clingon:command-arguments cmd)
    (let* ((outfmt (cli-kw-getopt cmd :outfmt))
           (colorless (clingon:getopt cmd :colorless)))
      (find-tag tag-rexpr outfmt colorless file-rexpr))))


(defun cli-tags-cmd-handler (cmd)
  (let* ((user (clingon:getopt cmd :user))
         (tag-dirs (clingon:getopt cmd :tag-dirs))
         (counters (clingon:getopt cmd :counters))
         (format-tag (if counters
                         (lambda (tag cnt) (format t "~A(~A)~%" tag cnt))
                         (lambda (tag cnt) (declare (ignorable cnt)) (format t "~A~%" tag)))))
    (cond
      (tag-dirs (loop :for d :in (uiop:subdirectories *tags-dir*)
                      :for dname = (last-path-component d)
                      :do (format t "~A~%" dname)))
      (user (let ((user-tags-ht (make-hash-table :test 'equal)))
              (loop :for d :in (uiop:subdirectories *tags-dir*)
                    :do (loop :for line :in (uiop:read-file-lines (merge-pathnames d "tags"))
                              :when (ppcre:scan "^user!" line)
                                :do (insert-or-combine user-tags-ht (subseq line (length "user!")) 1
                                                       :combine #'+)))
              (maphash format-tag user-tags-ht)))
      (t (let ((all-tags-ht (make-hash-table :test 'equal)))
           (loop :for d :in (uiop:subdirectories *tags-dir*)
                 :do (loop :for line :in (uiop:read-file-lines (merge-pathnames d "tags"))
                           :do (insert-or-combine all-tags-ht line 1 :combine #'+)))
           (maphash format-tag all-tags-ht))))))


(defun cli-autocomplete-cmd-handler (cmd)
  (declare (ignorable cmd))
  (let ((shell (cli-kw-getopt cmd :shell)))
    (ecase shell
      (:bash (format t (replace-all `(("<SCRIPT-NAME>" . ,*SCRIPT-NAME*) ("<SCRIPT-PATH>" . ,*SCRIPT-NAME*))
"
_easytags_auto_complete()
{
  local words
  local wN
  local w_1
  local w1
  wN=\"${COMP_WORDS[$COMP_CWORD]}\"
  w_1=\"${COMP_WORDS[$COMP_CWORD - 1]:-}\"
  w1=\"${COMP_WORDS[1]:-}\"
  case \"${w_1}\" in
    <SCRIPT-PATH>)
      words=\"tag tagged tags autocomplete\"
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
    tag)
      COMPREPLY=($(compgen -f -- \"$wN\"))
      ;;
    tagged)
      words=`<SCRIPT-PATH> tags -u`
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
    autocomplete)
      words=\"-s --shell\"
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
    -s | --shell)
      [ \"$w1\" = autocomplete ] && words=\"BASH ZSH\"
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
    -o | --outfmt)
      [ \"$w1\" = tagged ] && words=\"REPORT GREP EMACS XCONS CD\"
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
    -c | --colorless)
      [ \"$w1\" = tagged ] && words=\"y n\"
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
    *)
      [ \"$w1\" = tag ] && words=`<SCRIPT-PATH> tags -u`
      [ \"$w1\" = tagged ] && words=\"-o --outfmt -c --colorless\"
      COMPREPLY=($(compgen -W \"$words\" -- $wN))
      ;;
  esac
  return 0
}
complete -F _easytags_auto_complete <SCRIPT-PATH>
")))
      (:zsh (format t "Sorry, ZSH still is not supported~%")))))


(defun cli-tagged-cmd-opts ()
  (list
   (clingon:make-option
    :choice
    :description "output report format"
    :short-name #\o
    :long-name "outfmt"
    :key :outfmt
    :initial-value :xcons
    :items +outfmt+)
   (clingon:make-option
    :enum
    :description "suppress/force color"
    :short-name #\c
    :initial-value "-"
    :items +bool-enum-opt+
    :long-name "colorless"
    :key :colorless)))

(defun cli-tag-cmd-opts ()
  (list
   (clingon:make-option
    :flag
    :description "remove the tag"
    :short-name #\r
    :long-name "remove"
    :key :remove)
   (clingon:make-option
    :flag
    :description "move the tag"
    :short-name #\m
    :long-name "move"
    :key :move)))

(defun cli-tags-cmd-opts ()
  (list
   (clingon:make-option
    :flag
    :description "Print only user tags"
    :short-name #\u
    :long-name "user"
    :key :user)
   (clingon:make-option
    :flag
    :description "Print tags directories"
    :short-name #\t
    :long-name "tag-dirs"
    :key :tag-dirs)
   (clingon:make-option
    :flag
    :description "Counters of tags"
    :short-name #\c
    :long-name "counters"
    :key :counters)))


(defun cli-autocomplete-cmd-opts ()
  (list
   (clingon:make-option
    :choice
    :description "Shells for autocomplete"
    :short-name #\s
    :long-name "shell"
    :key :shell
    :initial-value :bash
    :items +ac-shell+)))


(defun cli-tag-cmd ()
  (clingon:make-command
   :name "tag"
   :usage "file/directory tag1 [tag...]"
   :examples '(("Tag a file:" . "tag some-file tag1 tag2 tag3"))
   :description "Tag file object"
   :handler #'cli-tag-cmd-handler
   :options (cli-tag-cmd-opts)))


(defun cli-tagged-cmd ()
  (clingon:make-command
   :name "tagged"
   :usage "[tag-regexp] [tag-file-regexp] [-o REPORT,GREP,EMACS,XCONS,CD] [-c 1,0]"
   :examples '(("List all tagged objects:" . "tagged")
               ("List by tag's regexp:" . "tagged 'tag[1-9]+'")
               ("List by specific tag's regexp:" . "tagged 'user!tag[1-9]+'")
               ("List by tag's regexp and tag-file's regexp:" . "tagged 'tag[1-9]+' 'somefile[0-9]+'")
               ("List with standard report:" . "tagged mytag -o REPORT")
               ("List with grep-like report:" . "tagged mytag -o GREP")
               ("List with grep-like report to Vim:" . "tagged mytag -o GREP|vim -")
               ("List with Emacs org-mode report in ZSH:" . "emacs =(SCRIPT tagged mytag -o GREP)")
               ("List with X console report supporting URL click:" . "tagged mytag -o XCONS")
               ("List with cd-commands report (copy-paste, execute):" . "tagged mytag -o CD")
               ("List suppressing color:" . "tagged mytag -c 0")
               ("List forcing color:" . "tagged mytag -c 1"))
   :description "Find tagged objects filtering them by regexps of tags, tag-file's full path"
   :handler #'cli-tagged-cmd-handler
   :options (cli-tagged-cmd-opts)))


(defun cli-tags-cmd ()
  (clingon:make-command
   :name "tags"
   :usage "[-s,-u]"
   :examples '(("List all known tags:" . "tags")
               ("List all user tags:" . "tags -u")
               ("List all tag directories:" . "tags -t"))
   :description "List tags"
   :handler #'cli-tags-cmd-handler
   :options (cli-tags-cmd-opts)))


(defun cli-autocomplete-cmd ()
  (clingon:make-command
   :name "autocomplete"
   :usage (format nil "[-s ~{~A~^,~}]" +ac-shell+)
   :examples '(("Inject autocomplete code in BASH shell" . "source <(SCRIPT autocomplete -s BASH)"))
   :description "Inject autocomplete code into the current shell"
   :handler #'cli-autocomplete-cmd-handler
   :options (cli-autocomplete-cmd-opts)))


(defun cli-main-cmd ()
  (clingon:make-command
   :name "tags"
   :description "Tags over file objects"
   :version "2.0.0"
   :authors '("John Doe <john.doe@example.org>")
   :license "BSD 2-Clause"
   :sub-commands (list (cli-tag-cmd) (cli-tagged-cmd) (cli-tags-cmd) (cli-autocomplete-cmd))
   :handler (lambda (cmd)
              (format t "No known subcommand provided!~%~%")
              (clingon:print-usage cmd *standard-output*)
              (uiop:quit 1))))


(defun full-argv ()
  (or
   #+sbcl sb-ext:*posix-argv*
   #+clisp ext:*args*
   #+cmu extensions:*command-line-words*
   #+allegro (sys:command-line-arguments)
   #+lispworks system:*line-arguments-list*
   nil))

;; Real exe:
;; ========
;; FMT = ("tagged" "java" "-o" "GREP") !!!! (".../easytag/easytags" "tagged" "java" "-o" "GREP")

;; Script:
;; =======
;; FMT = ("./easytags.ros" "tagged" "java" "-o" "GREP") !!!! (".../.roswell/impls/x86-64/linux/sbcl-bin/2.0.4/bin/sbcl")
;; (defun process-argv (argv)
;;   (let* ((fargv (full-argv))
;;          (buf (make-string 3))
;;          (arg0-file-header (handler-case ;; if we cannot read, return fake 3 item string
;;                             (with-open-file (strm (car argv) :direction :input)
;;                               (and (read-sequence buf strm) buf))
;;                              (error () (make-string 3)))))
;;     (cond ((string= "#!/" (subseq arg0-file-header 0 3)) (list :script (car argv)))
;;           (t (list :binary (car fargv))))))

;; ;;; MAIN
;; (defun main (&rest argv)
;;   ;; (trace tag-fs-object merge-pathnames ensure-directories-exist last-path-component xshash)
;;   (let* ((*tags-dir* (det-*tags-dir*))
;;          (*OS* (det-*OS*))
;;          (*path-sep* (det-*path-sep*))
;;          (argv1 (loop for arg in argv
;;                       if (string= arg "-h")
;;                         collect "--help"
;;                       else
;;                         collect arg))
;;          (qual-argv (process-argv argv1))
;;          (fixed-argv (ecase (car qual-argv)
;;                        (:script (rest argv))
;;                        (:binary argv))))
;;     (clingon:run (cli-main-cmd (nth 1 qual-argv)) fixed-argv)))

(defun executable-full-path ()  ;; XXX it seems it works
  (or (uiop:argv0)
      #+sbcl sb-ext:*core-pathname*
      #+ccl  ccl:*image-name*
      #+ecl  si::*argv0*
      "unknown"))

(defun executable-name ()
  (car (uiop:raw-command-line-arguments)))

(defun main ()
  (let* ((*tags-dir* (det-*tags-dir*))
         (*OS* (det-*OS*))
         (*path-sep* (det-*path-sep*))
         (argv (uiop:command-line-arguments))
         (argv1 (loop for arg in argv
                      if (string= arg "-h")
                        collect "--help"
                      else
                        collect arg)))
    (setf *SCRIPT-NAME* (executable-name))
    (clingon:run (cli-main-cmd) argv1)))



;;; vim: set ft=lisp lisp:
