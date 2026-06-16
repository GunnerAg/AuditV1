import type { NextApiRequest, NextApiResponse } from "next";
import apiAuth from "../../common/lib/authentication";
import { ethApiCall } from "../../common/lib/ethApiCall";
import { ConsensusAlgorithms, Clients } from "../../common/types/Validator";

// Esta sería una implementación simple. En producción, deberías usar una base de datos
let blacklistedValidators: Set<string> = new Set();

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const checkSession = await apiAuth(req, res);
  if (!checkSession) {
    return;
  }

  if (req.method === 'GET') {
    // Retornar lista de validadores bloqueados
    res.status(200).json({ 
      blacklisted: Array.from(blacklistedValidators) 
    });
  } else if (req.method === 'POST') {
    // Agregar validador a la lista negra
    const { address } = req.body;
    if (address) {
      blacklistedValidators.add(address.toLowerCase());
      res.status(200).json({ 
        message: `Validator ${address} added to blacklist`,
        blacklisted: Array.from(blacklistedValidators)
      });
    } else {
      res.status(400).json({ error: 'Address is required' });
    }
  } else if (req.method === 'DELETE') {
    // Remover validador de la lista negra
    const { address } = req.body;
    if (address) {
      blacklistedValidators.delete(address.toLowerCase());
      res.status(200).json({ 
        message: `Validator ${address} removed from blacklist`,
        blacklisted: Array.from(blacklistedValidators)
      });
    } else {
      res.status(400).json({ error: 'Address is required' });
    }
  } else {
    res.status(405).json({ error: 'Method not allowed' });
  }
}