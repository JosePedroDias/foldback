.PHONY: all lisp-bomberman lisp-sumo lisp-airhockey lisp-jumpnbump gateway test clean setup test-lisp test-gateway test-cross test-sumo-cross test-sumo-unit test-airhockey-cross test-jnb-cross benchmark check-lisp

all: lisp-bomberman gateway

setup:
	sbcl --eval "(ql:quickload :fset)" --eval "(ql:quickload :usocket)" --quit
	cd gateway && go mod download

check-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(uiop:quit)"

gateway:
	cd gateway && go run main.go

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

lisp-jumpnbump:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"jumpnbump\" :simulation-fn #'foldback:jnb-update :serialization-fn #'foldback:jnb-serialize :join-fn #'foldback:jnb-join :initial-custom-state (fset:map (:seed 123)))"

test: test-lisp test-gateway test-bomberman-cross test-sumo-unit test-sumo-cross test-airhockey-cross test-jnb-cross

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

test-bomberman-cross:
	@echo "--- Running Bomberman Cross-Platform Tests ---"
	node tests/bomberman-cross-test.js
	@echo "\n--- Running Bomberman Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/bomberman-cross-test.lisp

test-sumo-unit:
	@echo "--- Running Sumo Core Unit Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/sumo-unit-tests.lisp

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

test-jnb-cross:
	@echo "--- Running Jump and Bump Cross-Platform Tests (JS) ---"
	node tests/jumpnbump-cross-test.js
	@echo "\n--- Running Jump and Bump Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/jumpnbump-cross-test.lisp

benchmark:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --load tests/performance-bench.lisp
