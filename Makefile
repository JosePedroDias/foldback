.PHONY: all lisp lisp-bomberman lisp-sumo gateway test clean setup test-lisp test-gateway test-cross test-sumo-cross test-sumo-unit benchmark check-lisp

all: lisp gateway

lisp: lisp-bomberman

lisp-bomberman:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(let* ((level (foldback:make-bomberman-map)) (bots (foldback:spawn-bots level 3))) (foldback:start-server :game-id \"bomberman\" :simulation-fn #'foldback:bomberman-update :serialization-fn #'foldback:bomberman-serialize :join-fn #'foldback:bomberman-join :initial-custom-state (fset:map (:level level) (:bots bots) (:seed 123))))"

lisp-sumo:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"sumo\" :simulation-fn #'foldback:sumo-update :serialization-fn #'foldback:sumo-serialize :join-fn #'foldback:sumo-join)"

lisp-airhockey:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"airhockey\" :simulation-fn #'foldback:airhockey-update :serialization-fn #'foldback:airhockey-serialize :join-fn #'foldback:airhockey-join)"

check-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(uiop:quit)"

gateway:
	cd gateway && go run main.go

test: test-lisp test-gateway test-cross test-sumo-cross test-sumo-unit test-airhockey-cross

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
	@echo "--- Running Bomberman Cross-Platform Tests ---"
	node tests/cross-platform-test.js
	@echo "\n--- Running Bomberman Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/cross-platform-test.lisp

test-sumo-cross:
	@echo "--- Running Sumo Cross-Platform Tests (JS) ---"
	node tests/sumo-cross-test.js
	@echo "\n--- Running Sumo Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/sumo-cross-test.lisp

test-airhockey-cross:
	@echo "--- Running Air Hockey Cross-Platform Tests (JS) ---"
	node tests/airhockey-cross-test.js
	@echo "\n--- Running Air Hockey Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/airhockey-cross-test.lisp

test-sumo-unit:
	@echo "--- Running Sumo Core Unit Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/sumo-unit-tests.lisp

benchmark:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --load tests/performance-bench.lisp

setup:
	sbcl --eval "(ql:quickload :fset)" --eval "(ql:quickload :usocket)" --quit
	cd gateway && go mod download
