.PHONY: all lisp gateway test clean setup test-lisp test-gateway benchmark check-lisp

all: lisp gateway

lisp:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server)"

check-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(uiop:quit)"

gateway:
	cd gateway && go run main.go

test: test-lisp test-gateway

test-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/tests.lisp \
		 --load tests/physics-test.lisp \
		 --eval "(uiop:quit)"

test-gateway:
	cd gateway && go test -v ./...

benchmark:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --load tests/performance-bench.lisp

setup:
	sbcl --eval "(ql:quickload :fset)" --eval "(ql:quickload :usocket)" --quit
	cd gateway && go mod download
