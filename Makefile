.PHONY: all lisp gateway test clean setup test-lisp test-gateway test-cross benchmark check-lisp

all: lisp gateway

lisp:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(let* ((level (foldback:make-bomberman-map)) (bots (foldback:spawn-bots level 3))) (foldback:start-server :initial-custom-state (fset:map (:level level) (:bots bots) (:seed 123))))"

check-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(uiop:quit)"

gateway:
	cd gateway && go run main.go

test: test-lisp test-gateway test-cross

test-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/tests.lisp \
		 --load tests/physics-test.lisp \
		 --load tests/late-input-test.lisp \
		 --eval "(uiop:quit)"

test-gateway:
	cd gateway && go test -v ./...

test-cross:
	@echo "--- Running Cross-Platform Logic Sync Tests (JS) ---"
	node tests/cross-platform-test.js
	@echo "\n--- Running Cross-Platform Logic Sync Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/cross-platform-test.lisp

benchmark:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --load tests/performance-bench.lisp

setup:
	sbcl --eval "(ql:quickload :fset)" --eval "(ql:quickload :usocket)" --quit
	cd gateway && go mod download
