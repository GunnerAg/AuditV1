import fs from "fs";
import path from "path";

const defaultConfig = require("../../config/config.json");

export async function configReader() {
  if (process.env.QE_CONFIG_PATH) {
    const data = await fs.promises.readFile(
      `${process.env.QE_CONFIG_PATH}`,
      "utf8"
    );
    return data;
  } else {
    try {
      // Try to dynamically construct config from local QBFT network if present
      // Assumes project structure: <root>/explorer (this app), <root>/QBFT-Network (nodes)
      const projectRoot = path.resolve(process.cwd(), "..");
      const qbftNetworkDir = path.join(projectRoot, "QBFT-Network");

      const entries = await fs.promises.readdir(qbftNetworkDir, { withFileTypes: true });
      const nodeDirs = entries
        .filter((e) => e.isDirectory() && /^Node-\d+$/i.test(e.name))
        .map((e) => e.name)
        .sort((a, b) => {
          const na = parseInt(a.split("-")[1], 10);
          const nb = parseInt(b.split("-")[1], 10);
          return na - nb;
        });

      const nodes = [] as Array<{ name: string; client: string; rpcUrl: string; privateTxUrl: string }>;

      for (const nodeDir of nodeDirs) {
        const portsFile = path.join(qbftNetworkDir, nodeDir, "data", "besu.ports");
        try {
          const content = await fs.promises.readFile(portsFile, "utf8");
          const lines = content.split(/\r?\n/);
          const jsonRpcLine = lines.find((l) => /^json-rpc=\d+$/i.test(l.trim()));
          if (!jsonRpcLine) {
            continue;
          }
          const port = jsonRpcLine.split("=")[1];
          nodes.push({
            name: nodeDir.toLowerCase(),
            client: "besu",
            rpcUrl: `http://127.0.0.1:${port}`,
            privateTxUrl: "",
          });
        } catch (err) {
          // Skip nodes without ports file or unreadable
          continue;
        }
      }

      if (nodes.length > 0) {
        const dynamicConfig = {
          algorithm: "qbft",
          nodes,
        };
        return JSON.stringify(dynamicConfig);
      }
    } catch (e) {
      // Fall back to default below
    }

    return JSON.stringify(defaultConfig);
  }
}
