.PHONY: all lisp-bomberman lisp-airhockey lisp-jumpnbump lisp-pong lisp-tictactoe lisp-gofish gateway test test-all test-e2e clean setup test-lisp test-gateway test-bomberman-cross test-airhockey-cross test-airhockey-prediction test-jnb-cross test-pong-cross test-tictactoe test-gofish test-fixed-point test-bomberman-unit test-bomberman-respawn test-bomberman-stress benchmark check-lisp check-parens alive-lsp kill-servers kill-game kill-gateway

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

lisp-gofish:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"gofish\" :simulation-fn #'foldback:gf-update :serialization-fn #'foldback:gf-serialize :join-fn #'foldback:gf-join :tick-rate 10 :initial-custom-state (fset:map (:seed 12345)))"

lisp-tictactoe:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"tictactoe\" :simulation-fn #'foldback:ttt-update :serialization-fn #'foldback:ttt-serialize :join-fn #'foldback:ttt-join :tick-rate 10)"

test: test-lisp test-gateway test-engine test-server-flow test-bomberman-cross test-airhockey-cross test-airhockey-prediction test-jnb-cross test-pong-cross test-tictactoe test-gofish

test-lisp:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/bomberman-rollback-test.lisp \
		 --load tests/physics-test.lisp \
		 --eval "(uiop:quit)"

test-gateway:
	cd gateway && go test -v ./...

test-engine:
	@echo "--- Running Engine Reconciliation Tests (JS) ---"
	node tests/engine-test.js

test-server-flow:
	@echo "--- Running Server Flow Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/server-flow-test.lisp

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

test-tictactoe:
	@echo "--- Running Tic-Tac-Toe Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/tictactoe-test.lisp
	@echo "\n--- Running Tic-Tac-Toe Cross-Platform Tests (JS) ---"
	node tests/tictactoe-cross-test.js

test-gofish:
	@echo "--- Running Go Fish Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/gofish-test.lisp \
		 --load tests/gofish-serialize-dump.lisp
	@echo "\n--- Running Go Fish Cross-Platform Tests (JS) ---"
	node tests/gofish-cross-test.js

test-fixed-point:
	@echo "--- Running Fixed-Point Cross-Platform Tests (JS) ---"
	node tests/fixed-point-cross-test.js
	@echo "\n--- Running Fixed-Point Cross-Platform Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/fixed-point-cross-test.lisp

test-bomberman-unit:
	@echo "--- Running Bomberman Unit Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/bomberman-unit-test.lisp

test-bomberman-respawn:
	@echo "--- Running Bomberman Respawn Tests (Lisp) ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/bomberman-respawn-test.lisp

test-bomberman-stress:
	@echo "--- Running Bomberman Stress Test ---"
	sbcl --non-interactive \
		 --eval "(asdf:load-asd (truename \"foldback.asd\"))" \
		 --eval "(ql:quickload :foldback)" \
		 --load tests/bomberman-stress-test.lisp

test-e2e:
	@echo "--- Running Playwright E2E Tests (all games) ---"
	bash tests/run-e2e.sh

test-all: test-lisp test-gateway test-fixed-point test-bomberman-unit test-bomberman-respawn test-bomberman-cross test-airhockey-cross test-airhockey-prediction test-jnb-cross test-pong-cross test-bomberman-stress test-e2e

kill-game:
	-pkill -f "sbcl.*foldback"

kill-gateway:
	-lsof -ti :8080 | xargs -r kill

kill-servers: kill-game kill-gateway

benchmark:
	sbcl --non-interactive \
		 --load foldback.asd \
		 --load tests/performance-bench.lisp
