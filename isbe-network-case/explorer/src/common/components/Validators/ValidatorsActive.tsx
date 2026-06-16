import {
  Heading,
  Flex,
  Text,
  Button,
  Spacer,
  Box,
  Center,
  Skeleton,
  Badge,
  Tooltip,
} from "@chakra-ui/react";
import { useState } from "react";
import axios from "axios";
import { QuorumConfig, QuorumNode } from "../../types/QuorumConfig";
import { getDetailsByNodeName } from "../../lib/quorumConfig";
import { buttonState } from "../../types/Validator";
import { motion } from "framer-motion";
import getConfig from "next/config";
const { publicRuntimeConfig } = getConfig();

const MotionBox = motion(Box);
const MotionFlex = motion(Flex);
interface IProps {
  config: QuorumConfig;
  minersList: string[];
  selectedNode: string;
  blacklistedValidators: string[];
  nodeAddress: string;
}

export default function ValidatorsActive(props: IProps) {
  const [buttonLoading, setButtonLoading] = useState<buttonState>({});
  
  // Verificar si el nodo actual está en la lista negra
  const isCurrentNodeBlacklisted = props.blacklistedValidators.includes(props.nodeAddress.toLowerCase());

  const handleClick = async (e: any, index: number) => {
    // Verificar si el nodo actual está bloqueado
    if (isCurrentNodeBlacklisted) {
      console.error("Este validador ha sido expulsado y no puede proponer cambios");
      return;
    }

    setButtonLoading({ [index]: true });
    const needle: QuorumNode = getDetailsByNodeName(
      props.config,
      props.selectedNode
    );
    const rpcUrl: string = needle.rpcUrl;
    const client: string = needle.client;

    await axios({
      method: "POST",
      url: `/api/validatorsPropose`,
      headers: {
        "Content-Type": "application/json",
      },
      data: JSON.stringify({
        rpcUrl: rpcUrl,
        client: client,
        algorithm: props.config.algorithm,
        address: e,
        vote: false,
        proposerAddress: props.nodeAddress,
      }),
      baseURL: `${publicRuntimeConfig.QE_BASEPATH}`,
      timeout: 2000,
    })
      .then((res) => {
        if (res.status === 200) {
          console.log("Proposal to remove initiated: " + e);
        }
      })
      .catch((err) => {
        console.error(err);
        if (err.response?.status === 403) {
          console.error(err.response.data.message || "No tienes permisos para realizar esta acción");
        } else if (err.response?.status === 401) {
          console.error("No autorizado");
        }
      });

    setButtonLoading({ [index]: false });
  };

  return (
    <>
      <MotionBox
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.2 }}
        borderRadius="lg"
        borderWidth={2}
        boxShadow="lg"
        p={5}
        mx={2}
        my={3}
      >
        <Center mb={5}>
          <Heading size="lg">Active Validators</Heading>
        </Center>
        {props.minersList !== undefined && props.minersList.length > 0 ? (
          props.minersList.map((miner, i) => {
            const isBlacklisted = props.blacklistedValidators.includes(miner.toLowerCase());
            return (
              <>
                <MotionFlex
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.2 }}
                  m={3}
                  justifyContent="center"
                  alignItems="center"
                >
                  <Box flex="1">
                    <Text>{miner}</Text>
                    {isBlacklisted && (
                      <Badge colorScheme="red" ml={2}>
                        Expulsado
                      </Badge>
                    )}
                  </Box>
                  <Spacer key={i} />
                  <Tooltip 
                    label={isCurrentNodeBlacklisted ? "No puedes votar porque has sido expulsado" : ""} 
                    isDisabled={!isCurrentNodeBlacklisted}
                  >
                    <Button
                      colorScheme="red"
                      isLoading={buttonLoading[i] ? true : false}
                      loadingText="Removing..."
                      onClick={() => handleClick(miner, i)}
                      isDisabled={isCurrentNodeBlacklisted}
                    >
                      Remove
                    </Button>
                  </Tooltip>
                </MotionFlex>
              </>
            );
          })
        ) : (
          <>
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
            <Skeleton h="20px" m={2} />
          </>
        )}
      </MotionBox>
    </>
  );
}
