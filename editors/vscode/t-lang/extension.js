// T Language VS Code Extension
//
// Provides LSP integration by spawning the `t-lsp` language server and
// a convenience command to open the T REPL in an integrated terminal.
//
// The LSP client gives users tab completion, hover documentation,
// go-to-definition, and real-time diagnostics for .t files.

"use strict";

const vscode = require("vscode");
const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;

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
  const runRepl = vscode.commands.registerCommand("t-lang.runRepl", () => {
    const terminal =
      vscode.window.terminals.find((t) => t.name === "T REPL") ||
      vscode.window.createTerminal("T REPL");
    terminal.show();
    terminal.sendText("t repl");
  });

  const sendBuffer = vscode.commands.registerCommand(
    "t-lang.sendBuffer",
    () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      const terminal =
        vscode.window.terminals.find((t) => t.name === "T REPL") ||
        vscode.window.createTerminal("T REPL");
      terminal.show();
      terminal.sendText("t repl");
      // Small delay to let the REPL start, then send the file
      setTimeout(() => {
        terminal.sendText(`:load ${editor.document.fileName}`);
      }, 500);
    }
  );

  context.subscriptions.push(runRepl, sendBuffer);
}

function deactivate() {
  if (client) {
    return client.stop();
  }
}

module.exports = { activate, deactivate };
