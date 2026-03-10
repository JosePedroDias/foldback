;;;; alive-tcp-server.lisp — starts alive-lsp in TCP mode on a fixed port
;;;;
;;;; Usage: sbcl --script tools/alive-tcp-server.lisp
;;;;    or: sbcl --core tools/alive-lsp.core --script tools/alive-tcp-server.lisp
;;;;
;;;; The server listens on 127.0.0.1:4006 and accepts multiple connections.
;;;; Each connection gets a fresh LSP session.

(defvar *lsp-port* 4006)

;; Load quicklisp + alive-lsp (skip if using core image that already has it)
(unless (find-package :alive/server)
  (require :asdf)
  (load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
  (funcall (intern "QUICKLOAD" :ql) "alive-lsp" :silent t))

(format t "~&Starting alive-lsp TCP server on port ~A...~%" *lsp-port*)
(alive/server:start :port *lsp-port*)

;; Keep the process alive
(loop (sleep 3600))
