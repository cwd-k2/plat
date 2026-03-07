import * as path from "path";
import * as fs from "fs";
import {
  ExtensionContext,
  workspace,
  window,
  commands,
  StatusBarAlignment,
  StatusBarItem,
} from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
let statusBar: StatusBarItem;

export function activate(context: ExtensionContext): void {
  statusBar = window.createStatusBarItem(StatusBarAlignment.Left, 0);
  statusBar.text = "$(shield) plat-verify";
  statusBar.tooltip = "plat-verify language server";
  context.subscriptions.push(statusBar);

  const config = workspace.getConfiguration("plat-verify");

  const serverPath = config.get<string>("serverPath", "plat-verify");
  const configPath = config.get<string>("configPath", "plat-verify.toml");
  let manifestPath = config.get<string>("manifestPath", "");

  // Auto-detect manifest if not configured
  if (!manifestPath) {
    manifestPath = findManifest();
  }

  if (!manifestPath) {
    statusBar.text = "$(shield) plat-verify (no manifest)";
    statusBar.show();
    window.showWarningMessage(
      "plat-verify: no manifest found. Set plat-verify.manifestPath or place a *.plat.json file in the workspace."
    );
    return;
  }

  const serverOptions: ServerOptions = {
    command: serverPath,
    args: [manifestPath, "--config", configPath, "--lsp"],
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "go" },
      { scheme: "file", language: "typescript" },
      { scheme: "file", language: "rust" },
    ],
    synchronize: {
      fileEvents: workspace.createFileSystemWatcher("**/*.{go,ts,rs}"),
    },
  };

  client = new LanguageClient(
    "plat-verify",
    "plat-verify",
    serverOptions,
    clientOptions
  );

  client.start().then(
    () => {
      statusBar.text = "$(shield) plat-verify";
      statusBar.show();
    },
    (err) => {
      statusBar.text = "$(shield) plat-verify (error)";
      statusBar.show();
      window.showErrorMessage(`plat-verify failed to start: ${err.message}`);
    }
  );

  context.subscriptions.push(client);

  // Register restart command
  context.subscriptions.push(
    commands.registerCommand("plat-verify.restart", async () => {
      if (client) {
        await client.restart();
        window.showInformationMessage("plat-verify restarted");
      }
    })
  );
}

export async function deactivate(): Promise<void> {
  if (client) {
    await client.stop();
  }
}

function findManifest(): string | undefined {
  const workspaceFolders = workspace.workspaceFolders;
  if (!workspaceFolders) return undefined;

  for (const folder of workspaceFolders) {
    const root = folder.uri.fsPath;

    // Check for *.plat.json
    try {
      const files = fs.readdirSync(root);
      const platFile = files.find(
        (f) => f.endsWith(".plat.json") || f === "manifest.json"
      );
      if (platFile) {
        return path.join(root, platFile);
      }
    } catch {
      // ignore
    }
  }

  return undefined;
}
