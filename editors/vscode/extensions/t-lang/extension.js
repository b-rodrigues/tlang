// T Language VS Code Extension
//
// Provides LSP integration by spawning the `t-lsp` language server and
// convenience commands to interact with the T REPL from the editor.
//
// The LSP client gives users tab completion, hover documentation,
// go-to-definition, and real-time diagnostics for .t files.
//
// REPL commands:
//   t-lang.runRepl    – Open / focus the T REPL terminal.
//   t-lang.sendBuffer – Run the current file in the T REPL.
//   t-lang.sendLine   – Send the current line or selection to the T REPL
//                        and advance the cursor (RStudio-style Ctrl+Enter).

"use strict";

const vscode = require("vscode");
const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;

// ---------------------------------------------------------------------------
// Helper: get or create the T REPL terminal
// ---------------------------------------------------------------------------
function getTReplTerminal() {
  return (
    vscode.window.terminals.find((t) => t.name === "T REPL") ||
    vscode.window.createTerminal("T REPL")
  );
}

// ---------------------------------------------------------------------------
// Helper: ensure the T REPL is running, then return the terminal.
// If the terminal was just created, it sends `t repl` to start the REPL.
// ---------------------------------------------------------------------------
let replStarted = false;

function ensureRepl() {
  let terminal = vscode.window.terminals.find((t) => t.name === "T REPL");
  if (!terminal) {
    terminal = vscode.window.createTerminal("T REPL");
    terminal.sendText("t repl");
    replStarted = true;
  }
  return terminal;
}

// Reset the flag when the REPL terminal is closed so we re-start it next time.
vscode.window.onDidCloseTerminal((t) => {
  if (t.name === "T REPL") {
    replStarted = false;
  }
});

// ---------------------------------------------------------------------------
// Extension activation
// ---------------------------------------------------------------------------
function activate(context) {
  // --- LSP client --------------------------------------------------------
  const serverOptions = {
    command: "t-lsp",
    transport: TransportKind.stdio,
  };

  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "t" }],
  };

  client = new LanguageClient(
    "tlang",
    "T Language Server",
    serverOptions,
    clientOptions
  );

  client.start();

  // --- REPL commands -----------------------------------------------------

  // Open / focus the T REPL
  const runRepl = vscode.commands.registerCommand("t-lang.runRepl", () => {
    const terminal = ensureRepl();
    terminal.show();
  });

  // Run the entire current file in the T REPL
  const sendBuffer = vscode.commands.registerCommand(
    "t-lang.sendBuffer",
    () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      const terminal = ensureRepl();
      terminal.show();
      // Send the file contents via the run sub-command so no REPL
      // start-up race is possible.  Shell-quote the path so spaces
      // and special characters are handled safely.
      const quoted = editor.document.fileName.replace(/'/g, "'\\''");
      terminal.sendText(`t run '${quoted}'`);
    }
  );

  // Send current line or selection to the T REPL (RStudio-style).
  //
  // Behaviour:
  //   • If text is selected, send the selection (may span multiple lines).
  //   • If nothing is selected, send the current line.
  //   • After sending, move the cursor to the next non-empty line so the
  //     user can keep pressing Ctrl+Enter to step through a script.
  const sendLine = vscode.commands.registerCommand(
    "t-lang.sendLine",
    () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;

      const doc = editor.document;
      const sel = editor.selection;

      let text;
      if (!sel.isEmpty) {
        // Send the selected text verbatim.
        text = doc.getText(sel);
      } else {
        // Nothing selected — send the current line (trimmed of trailing
        // whitespace but preserving leading whitespace for multi-line
        // expressions pasted into the REPL).
        text = doc.lineAt(sel.active.line).text;
      }

      // Avoid sending blank lines to the REPL.
      if (text.trim().length === 0) {
        // Still advance the cursor so the user can skip blank lines.
        moveCursorDown(editor, sel.active.line);
        return;
      }

      const terminal = ensureRepl();
      terminal.show(/* preserveFocus */ true);
      terminal.sendText(text);

      // Advance the cursor to the next line (or the end of the selection).
      const lastLine = sel.isEmpty ? sel.active.line : sel.end.line;
      moveCursorDown(editor, lastLine);
    }
  );

  context.subscriptions.push(runRepl, sendBuffer, sendLine);
}

// ---------------------------------------------------------------------------
// Helper: move the cursor to the next non-empty line after `fromLine`.
// If there is no next non-empty line, move to the very last line.
// ---------------------------------------------------------------------------
function moveCursorDown(editor, fromLine) {
  const doc = editor.document;
  let target = fromLine + 1;

  // Skip blank lines so the cursor lands on the next meaningful line.
  while (target < doc.lineCount && doc.lineAt(target).isEmptyOrWhitespace) {
    target++;
  }

  // Clamp to the last line.
  if (target >= doc.lineCount) {
    target = doc.lineCount - 1;
  }

  const newPos = new vscode.Position(target, 0);
  editor.selection = new vscode.Selection(newPos, newPos);
  editor.revealRange(
    new vscode.Range(newPos, newPos),
    vscode.TextEditorRevealType.InCenterIfOutsideViewport
  );
}

// ---------------------------------------------------------------------------
// Deactivation
// ---------------------------------------------------------------------------
function deactivate() {
  if (client) {
    return client.stop();
  }
}

module.exports = { activate, deactivate };
