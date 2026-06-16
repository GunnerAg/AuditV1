import type { NextApiRequest, NextApiResponse } from "next";
import { NodeDetails } from "../../common/types/api/responses";
import { ethApiCall } from "../../common/lib/ethApiCall";
import apiAuth from "../../common/lib/authentication";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // console.log(req.body);
  const userClient = req.body.client;
  const rpcUrl = req.body.rpcUrl;
  let nodeDetails: NodeDetails = {
    statusText: "error",
    nodeId: "",
    nodeName: "",
    enode: "",
    ip: "",
    blocks: -1,
    peers: -1,
    queuedTxns: -1,
    pendingTxns: -1,
  };

  const checkSession = await apiAuth(req, res);
  if (!checkSession) {
    return;
  }

  try {
    // Get basic blockchain info first (these should always work)
    const ethBlockNumber = await ethApiCall(rpcUrl, "eth_blockNumber");
    const netPeerCount = await ethApiCall(rpcUrl, "net_peerCount");

    nodeDetails["blocks"] = parseInt(ethBlockNumber.data.result, 16);
    nodeDetails["peers"] = parseInt(netPeerCount.data.result, 16);

    // Try to get admin info (may not be enabled)
    try {
      const adminNodeInfo = await ethApiCall(rpcUrl, "admin_nodeInfo");
      if (adminNodeInfo.data && adminNodeInfo.data.result) {
        nodeDetails["nodeId"] = adminNodeInfo.data.result.id || "unknown";
        nodeDetails["nodeName"] = adminNodeInfo.data.result.name || "unknown";
        nodeDetails["enode"] = adminNodeInfo.data.result.enode || "unknown";
        nodeDetails["ip"] = adminNodeInfo.data.result.ip || "unknown";
      } else {
        // Admin API not available, use defaults
        nodeDetails["nodeId"] = "unknown";
        nodeDetails["nodeName"] = "unknown";
        nodeDetails["enode"] = "unknown";
        nodeDetails["ip"] = "unknown";
      }
    } catch (adminError) {
      console.log("Admin API not available for this node, using defaults");
      nodeDetails["nodeId"] = "unknown";
      nodeDetails["nodeName"] = "unknown";
      nodeDetails["enode"] = "unknown";
      nodeDetails["ip"] = "unknown";
    }

    // If we got here, the node is responding to basic RPC calls
    nodeDetails["statusText"] = "OK";

    // Try to get txpool info (may not be enabled)
    try {
      const txPoolStatus = await ethApiCall(
        rpcUrl,
        userClient === "goquorum" ? "txpool_status" : "txpool_besuTransactions"
      );
      // txpool results
      // besu = {"jsonrpc": "2.0", "id": 1, "result": [] }
      // goq = { "jsonrpc": "2.0", "id": 1, "result": : {pending: '0x0', queued: '0x0'} }
      const besuOrGoQTxns =
        userClient === "goquorum"
          ? parseInt(txPoolStatus.data.result.queued, 16)
          : txPoolStatus.data.result.length;

      nodeDetails["queuedTxns"] = besuOrGoQTxns;
      nodeDetails["pendingTxns"] = besuOrGoQTxns;
    } catch (txPoolError) {
      console.log(
        "TXPOOL API method is not enabled for this node, using default values"
      );
      nodeDetails["queuedTxns"] = 0;
      nodeDetails["pendingTxns"] = 0;
    }
  } catch (e) {
    console.error(e);
    console.error(
      "Node is unreachable. Ensure ports are open and client is running!"
    );
    nodeDetails["statusText"] = "error";
  } finally {
    res.status(200).json(nodeDetails);
    res.end();
  }
}
