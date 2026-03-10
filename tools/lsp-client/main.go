// lsp-client — a CLI tool to query an alive-lsp server over TCP.
//
// Standard LSP operations (require -file, some require -line -char):
//
//	go run tools/lsp-client/main.go -op documentSymbol -file src/state.lisp
//	go run tools/lsp-client/main.go -op hover -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op definition -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op references -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op completion -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op signatureHelp -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op selectionRange -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op semanticTokens -file src/state.lisp
//	go run tools/lsp-client/main.go -op rangeFormatting -file src/state.lisp -line 1 -char 1 -end-line 10 -end-char 1
//
// Custom alive-lsp operations:
//
//	go run tools/lsp-client/main.go -op eval -text '(+ 1 2)'
//	go run tools/lsp-client/main.go -op eval -text '(+ 1 2)' -pkg foldback
//	go run tools/lsp-client/main.go -op macroexpand -text '(defun foo () 1)'
//	go run tools/lsp-client/main.go -op macroexpand1 -text '(defun foo () 1)'
//	go run tools/lsp-client/main.go -op listPackages
//	go run tools/lsp-client/main.go -op listAsdfSystems
//	go run tools/lsp-client/main.go -op loadAsdfSystem -name foldback
//	go run tools/lsp-client/main.go -op compile -file src/state.lisp
//	go run tools/lsp-client/main.go -op loadFile -file src/state.lisp
//	go run tools/lsp-client/main.go -op tryCompile -file src/state.lisp
//	go run tools/lsp-client/main.go -op symbol -file src/state.lisp -line 3 -char 10
//	go run tools/lsp-client/main.go -op topFormBounds -file src/state.lisp -line 5 -char 1
//	go run tools/lsp-client/main.go -op surroundingFormBounds -file src/state.lisp -line 5 -char 1
//	go run tools/lsp-client/main.go -op packageForPosition -file src/state.lisp -line 3 -char 1
//	go run tools/lsp-client/main.go -op inspect -text '*package*'
//	go run tools/lsp-client/main.go -op inspectSymbol -pkg cl-user -symbol '*package*'
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var (
	port    = flag.Int("port", 4006, "LSP server port")
	op      = flag.String("op", "", "LSP operation (see usage)")
	file    = flag.String("file", "", "file path (relative or absolute)")
	line    = flag.Int("line", 1, "line number (1-based)")
	char    = flag.Int("char", 1, "character offset (1-based)")
	endLine = flag.Int("end-line", 0, "end line for range operations (1-based)")
	endChar = flag.Int("end-char", 0, "end character for range operations (1-based)")
	text    = flag.String("text", "", "text for eval/macroexpand/inspect")
	pkg     = flag.String("pkg", "", "package name for eval/macroexpand/inspect")
	name    = flag.String("name", "", "name for loadAsdfSystem")
	symbol  = flag.String("symbol", "", "symbol name for inspectSymbol")
	timeout = flag.Duration("timeout", 10*time.Second, "timeout for the entire operation")
)

// Operations that don't require a file
var noFileOps = map[string]bool{
	"eval": true, "macroexpand": true, "macroexpand1": true,
	"listPackages": true, "listAsdfSystems": true,
	"loadAsdfSystem": true, "inspect": true, "inspectSymbol": true,
}

// Operations that need position (line + char)
var positionOps = map[string]bool{
	"hover": true, "definition": true, "references": true,
	"completion": true, "signatureHelp": true, "selectionRange": true,
	"symbol": true, "topFormBounds": true, "surroundingFormBounds": true,
	"packageForPosition": true,
}

func main() {
	flag.Parse()

	if *op == "" {
		printUsage()
		os.Exit(1)
	}

	needsFile := !noFileOps[*op]
	if needsFile && *file == "" {
		fmt.Fprintf(os.Stderr, "error: -file is required for %s\n", *op)
		os.Exit(1)
	}

	var absFile, fileURI string
	if *file != "" {
		var err error
		absFile, err = filepath.Abs(*file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error resolving path: %v\n", err)
			os.Exit(1)
		}
		fileURI = "file://" + absFile
	}

	rootDir, _ := os.Getwd()
	rootURI := "file://" + rootDir

	conn, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(*port), 2*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error connecting to LSP server on port %d: %v\n", *port, err)
		fmt.Fprintln(os.Stderr, "hint: start the server with 'make alive-lsp'")
		os.Exit(1)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(*timeout))

	id := 1

	// 1. initialize
	initParams := map[string]any{
		"processId": nil,
		"capabilities": map[string]any{
			"textDocument": map[string]any{
				"documentSymbol": map[string]any{
					"hierarchicalDocumentSymbolSupport": true,
				},
			},
		},
		"rootUri": rootURI,
	}
	if _, err := sendRequest(conn, &id, "initialize", initParams); err != nil {
		fmt.Fprintf(os.Stderr, "initialize failed: %v\n", err)
		os.Exit(1)
	}

	// 2. initialized notification
	if err := sendNotification(conn, "initialized", map[string]any{}); err != nil {
		fmt.Fprintf(os.Stderr, "initialized notification failed: %v\n", err)
		os.Exit(1)
	}

	// 3. textDocument/didOpen (if we have a file)
	if absFile != "" {
		content, err := os.ReadFile(absFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error reading file %s: %v\n", absFile, err)
			os.Exit(1)
		}
		didOpenParams := map[string]any{
			"textDocument": map[string]any{
				"uri":        fileURI,
				"languageId": "commonlisp",
				"version":    1,
				"text":       string(content),
			},
		}
		if err := sendNotification(conn, "textDocument/didOpen", didOpenParams); err != nil {
			fmt.Fprintf(os.Stderr, "didOpen failed: %v\n", err)
			os.Exit(1)
		}
	}

	// 4. build and send the actual request
	method, params := buildRequest(*op, fileURI)

	result, err := sendRequest(conn, &id, method, params)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s failed: %v\n", method, err)
		os.Exit(1)
	}

	// 5. pretty-print result
	prettyPrint(*op, result)
}

func buildRequest(op, fileURI string) (method string, params any) {
	pos := map[string]any{"line": *line - 1, "character": *char - 1}
	textDocID := map[string]any{"uri": fileURI}
	textDocPos := map[string]any{"textDocument": textDocID, "position": pos}

	// alive-lsp custom methods use "text-document" (hyphenated)
	aliveTextDocPos := map[string]any{
		"text-document": textDocID,
		"position":      pos,
	}

	pkgName := *pkg
	if pkgName == "" {
		pkgName = "cl-user"
	}

	switch op {
	// --- Standard LSP ---
	case "documentSymbol":
		return "textDocument/documentSymbol", map[string]any{"textDocument": textDocID}
	case "hover":
		return "textDocument/hover", textDocPos
	case "definition":
		return "textDocument/definition", textDocPos
	case "references":
		return "textDocument/references", map[string]any{
			"textDocument": textDocID, "position": pos,
			"context": map[string]any{"includeDeclaration": true},
		}
	case "completion":
		return "textDocument/completion", textDocPos
	case "signatureHelp":
		return "textDocument/signatureHelp", textDocPos
	case "selectionRange":
		return "textDocument/selectionRange", map[string]any{
			"textDocument": textDocID,
			"positions":    []any{pos},
		}
	case "semanticTokens":
		return "textDocument/semanticTokens/full", map[string]any{"textDocument": textDocID}
	case "rangeFormatting":
		el, ec := *endLine, *endChar
		if el == 0 {
			el = *line + 10
		}
		if ec == 0 {
			ec = 1
		}
		return "textDocument/rangeFormatting", map[string]any{
			"textDocument": textDocID,
			"range": map[string]any{
				"start": pos,
				"end":   map[string]any{"line": el - 1, "character": ec - 1},
			},
			"options": map[string]any{"tabSize": 2, "insertSpaces": true},
		}

	// --- Custom alive-lsp ---
	case "eval":
		p := map[string]any{"text": *text, "package": pkgName}
		return "$/alive/eval", p
	case "macroexpand":
		return "$/alive/macroexpand", map[string]any{"text": *text, "package": pkgName}
	case "macroexpand1":
		return "$/alive/macroexpand1", map[string]any{"text": *text, "package": pkgName}
	case "listPackages":
		return "$/alive/listPackages", map[string]any{}
	case "listAsdfSystems":
		return "$/alive/listAsdfSystems", map[string]any{}
	case "loadAsdfSystem":
		return "$/alive/loadAsdfSystem", map[string]any{"name": *name}
	case "compile":
		return "$/alive/compile", map[string]any{"path": fileURI}
	case "loadFile":
		return "$/alive/loadFile", map[string]any{"path": fileURI}
	case "tryCompile":
		return "$/alive/tryCompile", map[string]any{"path": fileURI}
	case "symbol":
		return "$/alive/symbol", aliveTextDocPos
	case "topFormBounds":
		return "$/alive/topFormBounds", aliveTextDocPos
	case "surroundingFormBounds":
		return "$/alive/surroundingFormBounds", aliveTextDocPos
	case "packageForPosition":
		return "$/alive/getPackageForPosition", aliveTextDocPos
	case "inspect":
		return "$/alive/inspect", map[string]any{"text": *text, "package": pkgName}
	case "inspectSymbol":
		return "$/alive/inspectSymbol", map[string]any{"package": *pkg, "symbol": *symbol}

	default:
		fmt.Fprintf(os.Stderr, "unknown operation: %s\n", op)
		os.Exit(1)
		return "", nil
	}
}

func printUsage() {
	fmt.Fprintln(os.Stderr, `Usage: lsp-client -op <operation> [options]

Standard LSP (require -file):
  documentSymbol    List symbols in a file
  hover             Hover info at position (-line -char)
  definition        Go to definition (-line -char)
  references        Find references (-line -char)
  completion        Completions at position (-line -char)
  signatureHelp     Signature help at position (-line -char)
  selectionRange    Selection range at position (-line -char)
  semanticTokens    Semantic tokens for file
  rangeFormatting   Format range (-line -char -end-line -end-char)

Custom alive-lsp:
  eval              Evaluate Lisp (-text, optional -pkg)
  macroexpand       Macro-expand (-text, optional -pkg)
  macroexpand1      Macro-expand-1 (-text, optional -pkg)
  listPackages      List all packages
  listAsdfSystems   List ASDF systems
  loadAsdfSystem    Load ASDF system (-name)
  compile           Compile file (-file)
  loadFile          Load file (-file)
  tryCompile        Try-compile file (-file)
  symbol            Symbol info at position (-file -line -char)
  topFormBounds     Top form bounds (-file -line -char)
  surroundingFormBounds  Surrounding form bounds (-file -line -char)
  packageForPosition     Package at position (-file -line -char)
  inspect           Inspect expression (-text, optional -pkg)
  inspectSymbol     Inspect symbol (-pkg -symbol)`)
}

// --- LSP protocol helpers ---

func sendRequest(conn net.Conn, id *int, method string, params any) (json.RawMessage, error) {
	reqID := *id
	*id++

	msg := map[string]any{
		"jsonrpc": "2.0",
		"id":      reqID,
		"method":  method,
		"params":  params,
	}

	if err := writeMessage(conn, msg); err != nil {
		return nil, fmt.Errorf("write: %w", err)
	}

	for {
		body, err := readMessage(conn)
		if err != nil {
			return nil, fmt.Errorf("read: %w", err)
		}

		var envelope struct {
			ID     *int             `json:"id"`
			Result json.RawMessage  `json:"result"`
			Error  *json.RawMessage `json:"error"`
		}
		if err := json.Unmarshal(body, &envelope); err != nil {
			return nil, fmt.Errorf("unmarshal: %w", err)
		}

		// Skip notifications (no id)
		if envelope.ID == nil {
			continue
		}
		if *envelope.ID != reqID {
			continue
		}
		if envelope.Error != nil {
			return nil, fmt.Errorf("LSP error: %s", string(*envelope.Error))
		}
		return envelope.Result, nil
	}
}

func sendNotification(conn net.Conn, method string, params any) error {
	msg := map[string]any{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
	}
	return writeMessage(conn, msg)
}

func writeMessage(conn net.Conn, msg any) error {
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	header := fmt.Sprintf("Content-Length: %d\r\n\r\n", len(body))
	_, err = conn.Write(append([]byte(header), body...))
	return err
}

func readMessage(conn net.Conn) ([]byte, error) {
	var headerBuf []byte
	for {
		b := make([]byte, 1)
		if _, err := conn.Read(b); err != nil {
			return nil, err
		}
		headerBuf = append(headerBuf, b[0])
		if len(headerBuf) >= 4 && string(headerBuf[len(headerBuf)-4:]) == "\r\n\r\n" {
			break
		}
	}

	headerStr := string(headerBuf)
	var contentLength int
	for _, hdrLine := range strings.Split(headerStr, "\r\n") {
		if after, ok := strings.CutPrefix(hdrLine, "Content-Length:"); ok {
			contentLength, _ = strconv.Atoi(strings.TrimSpace(after))
		}
	}
	if contentLength == 0 {
		return nil, fmt.Errorf("no Content-Length in headers: %q", headerStr)
	}

	body := make([]byte, contentLength)
	read := 0
	for read < contentLength {
		n, err := conn.Read(body[read:])
		if err != nil {
			return nil, err
		}
		read += n
	}
	return body, nil
}

// --- Pretty-printing ---

func prettyPrint(op string, result json.RawMessage) {
	if string(result) == "null" {
		fmt.Println("No results.")
		return
	}

	switch op {
	case "documentSymbol":
		printDocumentSymbols(result)
	case "hover":
		printHover(result)
	case "definition", "references":
		printLocations(result)
	case "completion":
		printCompletions(result)
	case "eval":
		printEval(result)
	case "macroexpand", "macroexpand1":
		printMacroExpand(result)
	case "listPackages":
		printPackages(result)
	case "listAsdfSystems":
		printAsdfSystems(result)
	case "symbol":
		printSymbolInfo(result)
	case "topFormBounds", "surroundingFormBounds":
		printBounds(result)
	default:
		printRaw(result)
	}
}

func printDocumentSymbols(result json.RawMessage) {
	var symbols []struct {
		Name     string `json:"name"`
		Kind     int    `json:"kind"`
		Range    Range  `json:"range"`
		Children []struct {
			Name  string `json:"name"`
			Kind  int    `json:"kind"`
			Range Range  `json:"range"`
		} `json:"children"`
	}
	if err := json.Unmarshal(result, &symbols); err != nil {
		var flat []struct {
			Name     string `json:"name"`
			Kind     int    `json:"kind"`
			Location struct {
				Range Range `json:"range"`
			} `json:"location"`
		}
		if err2 := json.Unmarshal(result, &flat); err2 != nil {
			printRaw(result)
			return
		}
		for _, s := range flat {
			fmt.Printf("  %s %s  (line %d)\n", symbolKind(s.Kind), s.Name, s.Location.Range.Start.Line+1)
		}
		return
	}
	for _, s := range symbols {
		fmt.Printf("  %s %s  (line %d)\n", symbolKind(s.Kind), s.Name, s.Range.Start.Line+1)
		for _, c := range s.Children {
			fmt.Printf("    %s %s  (line %d)\n", symbolKind(c.Kind), c.Name, c.Range.Start.Line+1)
		}
	}
}

func printHover(result json.RawMessage) {
	var hover struct {
		Contents any `json:"contents"`
	}
	if err := json.Unmarshal(result, &hover); err != nil {
		printRaw(result)
		return
	}
	switch v := hover.Contents.(type) {
	case string:
		fmt.Println(v)
	case map[string]any:
		if val, ok := v["value"]; ok {
			fmt.Println(val)
		} else {
			printRaw(result)
		}
	default:
		printRaw(result)
	}
}

func printLocations(result json.RawMessage) {
	var locs []struct {
		URI   string `json:"uri"`
		Range Range  `json:"range"`
	}
	if err := json.Unmarshal(result, &locs); err != nil {
		var loc struct {
			URI   string `json:"uri"`
			Range Range  `json:"range"`
		}
		if err2 := json.Unmarshal(result, &loc); err2 != nil {
			printRaw(result)
			return
		}
		locs = append(locs, loc)
	}
	cwd, _ := os.Getwd()
	for _, loc := range locs {
		path := strings.TrimPrefix(loc.URI, "file://")
		if cwd != "" {
			if rel, err := filepath.Rel(cwd, path); err == nil {
				path = rel
			}
		}
		fmt.Printf("  %s:%d:%d\n", path, loc.Range.Start.Line+1, loc.Range.Start.Character+1)
	}
}

func printCompletions(result json.RawMessage) {
	// completionList or []completionItem
	var list struct {
		Items []completionItem `json:"items"`
	}
	if err := json.Unmarshal(result, &list); err == nil && len(list.Items) > 0 {
		for _, item := range list.Items {
			printCompletionItem(item)
		}
		return
	}
	var items []completionItem
	if err := json.Unmarshal(result, &items); err == nil {
		for _, item := range items {
			printCompletionItem(item)
		}
		return
	}
	printRaw(result)
}

type completionItem struct {
	Label  string `json:"label"`
	Kind   int    `json:"kind"`
	Detail string `json:"detail"`
}

func printCompletionItem(item completionItem) {
	detail := ""
	if item.Detail != "" {
		detail = "  — " + item.Detail
	}
	fmt.Printf("  %s%s\n", item.Label, detail)
}

func printEval(result json.RawMessage) {
	// alive-lsp returns eval results as an array of strings or a text field
	var text []string
	if err := json.Unmarshal(result, &text); err == nil {
		for _, line := range text {
			fmt.Println(line)
		}
		return
	}
	var obj map[string]any
	if err := json.Unmarshal(result, &obj); err == nil {
		if t, ok := obj["text"]; ok {
			fmt.Println(t)
			return
		}
	}
	printRaw(result)
}

func printMacroExpand(result json.RawMessage) {
	var s string
	if err := json.Unmarshal(result, &s); err == nil {
		fmt.Println(s)
		return
	}
	var obj map[string]any
	if err := json.Unmarshal(result, &obj); err == nil {
		if t, ok := obj["text"]; ok {
			fmt.Println(t)
			return
		}
	}
	printRaw(result)
}

func printPackages(result json.RawMessage) {
	var pkgs []any
	if err := json.Unmarshal(result, &pkgs); err == nil {
		for _, p := range pkgs {
			switch v := p.(type) {
			case string:
				fmt.Printf("  %s\n", v)
			case map[string]any:
				if name, ok := v["name"]; ok {
					fmt.Printf("  %s\n", name)
				} else {
					fmt.Printf("  %v\n", v)
				}
			default:
				fmt.Printf("  %v\n", v)
			}
		}
		return
	}
	printRaw(result)
}

func printAsdfSystems(result json.RawMessage) {
	printPackages(result) // same shape
}

func printSymbolInfo(result json.RawMessage) {
	printRaw(result)
}

func printBounds(result json.RawMessage) {
	var bounds struct {
		Start Position `json:"start"`
		End   Position `json:"end"`
	}
	if err := json.Unmarshal(result, &bounds); err == nil {
		fmt.Printf("  start: line %d, char %d\n", bounds.Start.Line+1, bounds.Start.Character+1)
		fmt.Printf("  end:   line %d, char %d\n", bounds.End.Line+1, bounds.End.Character+1)
		return
	}
	printRaw(result)
}

type Range struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

type Position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

func printRaw(data json.RawMessage) {
	var pretty any
	if err := json.Unmarshal(data, &pretty); err == nil {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		enc.Encode(pretty)
	} else {
		fmt.Println(string(data))
	}
}

func symbolKind(kind int) string {
	kinds := map[int]string{
		1: "file", 2: "module", 3: "namespace", 4: "package",
		5: "class", 6: "method", 7: "property", 8: "field",
		9: "constructor", 10: "enum", 11: "interface", 12: "function",
		13: "variable", 14: "constant", 15: "string", 16: "number",
		17: "boolean", 18: "array", 19: "object", 20: "key",
		21: "null", 22: "enum-member", 23: "struct", 24: "event",
		25: "operator", 26: "type-param",
	}
	if name, ok := kinds[kind]; ok {
		return name
	}
	return fmt.Sprintf("kind(%d)", kind)
}
