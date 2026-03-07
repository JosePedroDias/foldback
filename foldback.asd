(asdf:defsystem #:foldback
  :description "An authoritative functional game server engine with rollback."
  :author "Gemini CLI"
  :license "MIT"
  :depends-on (#:fset #:usocket)
  :serial t
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "utils")
                 (:file "state")
                 (:file "physics")
                 (:file "map")
                 (:file "bombs")
                 (:file "bots")
                 (:file "bomberman")
                 (:file "engine")
                 (:file "server")))))
