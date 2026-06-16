import type { NextApiRequest, NextApiResponse } from "next";
import apiAuth from "../../common/lib/authentication";
import { ethApiCall } from "../../common/lib/ethApiCall";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const client = req.body.client;
  const rpcUrl = req.body.rpcUrl;

  const checkSession = await apiAuth(req, res);
  if (!checkSession) {
    return;
  }

  try {
    // Obtener información del nodo para extraer su dirección
    const nodeInfo = await ethApiCall(rpcUrl, "admin_nodeInfo", []);
    
    if (nodeInfo.data && nodeInfo.data.result && nodeInfo.data.result.enode) {
      // Extraer la clave pública del enode
      const enode = nodeInfo.data.result.enode;
      const pubKeyMatch = enode.match(/^enode:\/\/([a-fA-F0-9]{128})/);
      
      if (pubKeyMatch) {
        const pubKey = pubKeyMatch[1];
        // En un entorno real, necesitarías convertir la clave pública a dirección
        // Por ahora, usaremos una implementación simplificada
        const keccak = require('keccak');
        const publicKeyBytes = Buffer.from(pubKey, 'hex');
        const hash = keccak('keccak256').update(publicKeyBytes).digest();
        const address = '0x' + hash.slice(-20).toString('hex');
        
        res.status(200).json({ address: address });
        return;
      }
    }

    // Método alternativo: intentar obtener la dirección directamente del nodo
    const accounts = await ethApiCall(rpcUrl, "eth_accounts", []);
    if (accounts.data && accounts.data.result && accounts.data.result.length > 0) {
      res.status(200).json({ address: accounts.data.result[0] });
      return;
    }

    res.status(404).json({ error: "Could not determine node address" });
  } catch (e) {
    console.error(e);
    console.error("Node is unreachable or method not supported");
    res.status(500).json({ 
      error: "NODE_UNREACHABLE",
      message: "No se pudo obtener la dirección del nodo"
    });
  }
}