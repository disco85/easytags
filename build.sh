#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT="$(basename "$SCRIPT_DIR")"
PROJECT_L="$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]')"
PROJECT_U="$(printf '%s' "$PROJECT" | tr '[:lower:]' '[:upper:]')"

LISP_CMD=${1:-qlot exec sbcl}
LOGFILE=build.log
: > "$LOGFILE"

# Increase heap if your image is large (adjust MB)
DYNAMIC_SPACE=${DYNAMIC_SPACE:-4096}
# runtime vs lisp options
SBCL_RUNTIME_OPTS=(--dynamic-space-size "$DYNAMIC_SPACE")
SBCL_LISP_OPTS=(--noinform --no-sysinit --noprint)

if [[ "${RELEASE+x}" = x ]]; then
  SBCL_LISP_OPTS+=(--disable-debugger)
  SAVE_EXTRA=":purify t :compression t"
else
  SBCL_LISP_OPTS+=() #--debug 3)
  SAVE_EXTRA=""
fi

read -r -d '' LISP_CODE <<EOF || true
(progn
  (require :asdf)
  (defun write-log (s)
    (with-open-file (out "/tmp/${PROJECT_L}-build.log"
                         :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
      (format out "~A~%" s) (finish-output)))
  (write-log "=== build started ===")
  (write-log (format nil "cwd: ~A" (uiop:getcwd)))

  (write-log "about to asdf:load-system :${PROJECT_L}")
;  (load "${PROJECT_L}.asd")
  (asdf:load-system :${PROJECT_L})
;  (write-log "asdf:load-system returned")
  (write-log (format nil "asdf search path: ~A" (asdf:system-source-directory :asdf)))
  (write-log (format nil "find-system: ~S" (asdf:find-system :${PROJECT_L})))
  (let ((toplevel-sym (or (find-symbol "MAIN" "${PROJECT_U}")
                          (intern "MAIN" "${PROJECT_U}"))))
    (write-log (format nil "toplevel symbol: ~S" toplevel-sym))
    (write-log "about to save-lisp-and-die")
    (sb-ext:save-lisp-and-die "${PROJECT_L}"
      :executable t
      :save-runtime-options t
      :toplevel toplevel-sym
      SAVE-EXTRA)))
EOF

LISP_CODE="${LISP_CODE//SAVE-EXTRA/$SAVE_EXTRA}"

echo "---- Lisp code to be evaluated ----" | tee -a "$LOGFILE"
printf '%s\n' "$LISP_CODE" | tee -a "$LOGFILE"
echo "---- end of code ----" | tee -a "$LOGFILE"

echo "$LISP_CODE" > "/tmp/${PROJECT_L}-build.lisp"

# Run under qlot exec if you rely on qlot local projects
echo "About to run $LISP_CMD ${SBCL_RUNTIME_OPTS[@]} ${SBCL_LISP_OPTS[@]} --load /tmp/${PROJECT_L}-build.lisp" | tee -a "$LOGFILE"
$LISP_CMD "${SBCL_RUNTIME_OPTS[@]}" "${SBCL_LISP_OPTS[@]}" --load "/tmp/${PROJECT_L}-build.lisp" |tee -a "$LOGFILE" 2>&1
