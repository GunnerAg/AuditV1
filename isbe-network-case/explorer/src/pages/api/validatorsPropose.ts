import type { NextApiRequest, NextApiResponse } from "next";
import apiAuth from "../../common/lib/authentication";
import { ethApiCall } from "../../common/lib/ethApiCall";
import { ConsensusAlgorithms, Clients } from "../../common/types/Validator";

// Temporalmente comentado para debugging
// import fs from 'fs';
// import path from 'path';

// const getBlacklistedValidators = (): Set<string> => {
//   try {
//     const filePath = path.join(process.cwd(), 'data', 'blacklisted-validators.json');
//     if (fs.existsSync(filePath)) {
//       const data = fs.readFileSync(filePath, 'utf8');
//       return new Set(JSON.parse(data));
//     }
//   } catch (error) {
//     console.error('Error reading blacklisted validators:', error);
//   }
//   return new Set();
// };

// const saveBlacklistedValidators = (blacklisted: Set<string>) => {
//   try {
//     const dataDir = path.join(process.cwd(), 'data');
//     if (!fs.existsSync(dataDir)) {
//       fs.mkdirSync(dataDir, { recursive: true });
//     }
//     const filePath = path.join(dataDir, 'blacklisted-validators.json');
//     fs.writeFileSync(filePath, JSON.stringify(Array.from(blacklisted), null, 2));
//   } catch (error) {
//     console.error('Error saving blacklisted validators:', error);
//   }
// };

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  // console.log(req.body);
  const client = req.body.client;
  const algorithm = req.body.algorithm;
  const rpcUrl = req.body.rpcUrl;
  const address = req.body.address;
  const vote: Boolean = req.body.vote; // true to vote in, false to vote out
  const methodDict: Clients = {
    goquorum: {
      qbft: "istanbul_propose",
      ibft: "istanbul_propose",
      raft: "raft_addPeer",
    },
    besu: {
      clique: "clique_proposals",
      ibft: "ibft_proposeValidatorVote",
      qbft: "qbft_proposeValidatorVote",
    },
  };

  const checkSession = await apiAuth(req, res);
  if (!checkSession) {
    return;
  }

  try {
    const result = await ethApiCall(
      rpcUrl,
      methodDict[client as keyof Clients][
        algorithm as keyof ConsensusAlgorithms
      ]!,
      [address, vote]
    );
    console.log(result);
    res.status(200);
  } catch (e) {
    console.error(e);
    console.error(
      "Node is unreachable. Ensure ports are open and client is running!"
    );
    res.status(500).json({});
  } finally {
    res.end();
  }
}
