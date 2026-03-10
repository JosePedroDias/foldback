.PHONY: all lisp-bomberman lisp-airhockey lisp-jumpnbump lisp-pong gateway test test-all test-e2e clean setup test-lisp test-gateway test-bomberman-cross test-airhockey-cross test-airhockey-prediction test-jnb-cross test-pong-cross test-fixed-point test-unit test-respawn test-bomb-mechanics test-stress benchmark check-lisp check-parens alive-lsp

all: lisp-bomberman gateway

setup:
	sbcl --eval "(ql:quickload :fset)" --eval "(ql:quickload :usocket)" --quit
	cd gateway && go mod download

alive-lsp: build-lsp-client
	sbcl --script tools/alive-tcp-server.lisp

build-lsp-client:
	cd tools/lsp-client && go build -o lsp-client .

check-parens:
	go run scripts/check-parens.go src/*.lisp src/games/*.lisp

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

lisp-airhockey:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"airhockey\" :simulation-fn #'foldback:airhockey-update :serialization-fn #'foldback:airhockey-serialize :join-fn #'foldback:airhockey-join)"

lisp-jumpnbump:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"jumpnbump\" :simulation-fn #'foldback:jnb-update :serialization-fn #'foldback:jnb-serialize :join-fn #'foldback:jnb-join :initial-custom-state (fset:map (:seed 123)))"

lisp-pong:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"pong\" :simulation-fn #'foldback:pong-update :serialization-fn #'foldback:pong-serialize :join-fn #'foldback:pong-join)"

test: test-lisp test-gateway test-bomberman-cross test-airhockey-cross test-airhockey-prediction test-jnb-cross test-pong-cross

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

test-airhockey-cross:
	@echo "--- Running Air Hockey Cross-Platform Tests (JS) ---"
	node tests/airhockey-cross-test.js
	@echo "\n--- Running Air Hockey Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/airhockey-cross-test.lisp

test-airhockey-prediction:
	@echo "--- Running Air Hockey Late-Input Rollback Test (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/airhockey-prediction-test.lisp

test-jnb-cross:
	@echo "--- Running Jump and Bump Cross-Platform Tests (JS) ---"
	node tests/jumpnbump-cross-test.js
	@echo "\n--- Running Jump and Bump Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/jumpnbump-cross-test.lisp

test-pong-cross:
	@echo "--- Running Pong Cross-Platform Tests (JS) ---"
	node tests/pong-cross-test.js
	@echo "\n--- Running Pong Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/pong-cross-test.lisp

test-fixed-point:
	@echo "--- Running Fixed-Point Cross-Platform Tests (JS) ---"
	node tests/fixed-point-cross-test.js
	@echo "\n--- Running Fixed-Point Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/fixed-point-cross-test.lisp

test-unit:
	@echo "--- Running Granular Unit Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/unit-tests.lisp

test-respawn:
	@echo "--- Running Respawn Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/respawn-test.lisp

test-bomb-mechanics:
	@echo "--- Running Bomb Mechanics Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/bomb-mechanics-test.lisp

test-stress:
	@echo "--- Running Stress Test ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/stress-test.lisp

test-e2e:
	@echo "--- Running Playwright E2E Tests (all games) ---"
	bash tests/run-e2e.sh

test-all: test-lisp test-gateway test-fixed-point test-unit test-respawn test-bomb-mechanics test-bomberman-cross test-airhockey-cross test-airhockey-prediction test-jnb-cross test-pong-cross test-stress test-e2e

benchmark:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --load tests/performance-bench.lisp
