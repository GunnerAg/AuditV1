import { useCallback, useEffect, useState, useRef } from "react";
import { GetServerSideProps } from "next";
import type { Session } from "next-auth";
import { useSession, getSession } from "next-auth/react";
import AccessDenied from "../common/components/Misc/AccessDenied";
import { Divider, Container, SimpleGrid, Alert, AlertIcon, AlertTitle, AlertDescription, Box } from "@chakra-ui/react";
import PageHeader from "../common/components/Misc/PageHeader";
import axios from "axios";
import { QuorumConfig, QuorumNode } from "../common/types/QuorumConfig";
import ValidatorsActive from "../common/components/Validators/ValidatorsActive";
import ValidatorsPending from "../common/components/Validators/ValidatorsPending";
import ValidatorsPropose from "../common/components/Validators/ValidatorsPropose";
import ValidatorsAbout from "../common/components/Validators/ValidatorAbout";
import { getDetailsByNodeName } from "../common/lib/quorumConfig";
import { refresh3s } from "../common/lib/common";
import { configReader } from "../common/lib/getConfig";
import getConfig from "next/config";
const { publicRuntimeConfig } = getConfig();

interface IState {
  selectedNode: string;
  rpcUrl: string;
  minersList: string[];
  pendingList: string[];
  blacklistedValidators: string[];
  nodeAddress: string;
}

interface IProps {
  config: QuorumConfig;
}

export default function Validators({ config }: IProps) {
  const isAuthEnabled = publicRuntimeConfig.DISABLE_AUTH === "false";
  const { data: session, status } = isAuthEnabled ? useSession() : { data: null, status: "unauthenticated" };
  const loading = isAuthEnabled && status === "loading";

  const controller = new AbortController();
  const intervalRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [validators, setValidators] = useState<IState>({
    selectedNode: config.nodes[0].name,
    rpcUrl: config.nodes[0].rpcUrl,
    minersList: [],
    pendingList: [],
    blacklistedValidators: [],
    nodeAddress: "",
  });

  const nodeInfoHandler = useCallback(async (node: string) => {
    const needle: QuorumNode = getDetailsByNodeName(config, node);

    return Promise.all([
      axios({
        method: "POST",
        url: `/api/validatorsGetCurrent`,
        headers: {
          "Content-Type": "application/json",
        },
        data: JSON.stringify({
          rpcUrl: needle.rpcUrl,
          client: needle.client,
          algorithm: config.algorithm,
        }),
        signal: controller.signal,
        baseURL: `${publicRuntimeConfig.QE_BASEPATH}`,
      }),

      axios({
        method: "POST",
        url: `/api/validatorsGetPendingVotes`,
        headers: {
          "Content-Type": "application/json",
        },
        data: JSON.stringify({
          rpcUrl: needle.rpcUrl,
          client: needle.client,
          algorithm: config.algorithm,
        }),
        baseURL: `${publicRuntimeConfig.QE_BASEPATH}`,
      }),
    ])
      .then(([currentVal, pendingVal]) => {
        setValidators({
          selectedNode: node,
          rpcUrl: needle.rpcUrl,
          minersList: currentVal.data.validators,
          pendingList: pendingVal.data.validators,
          blacklistedValidators: [], // Por ahora mantener vacío
          nodeAddress: "", // Por ahora mantener vacío
        });
      })
      .catch((err) => {
        if (err.status === 401) {
          console.error(`${err.status} Unauthorized`);
        }
        setValidators({
          selectedNode: node,
          rpcUrl: needle.rpcUrl,
          minersList: [],
          pendingList: [],
          blacklistedValidators: [],
          nodeAddress: "",
        });
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    nodeInfoHandler(validators.selectedNode);
    intervalRef.current = setInterval(() => {
      nodeInfoHandler(validators.selectedNode);
      console.log("validators > called for new info...");
    }, refresh3s);

    return () => {
      clearInterval(intervalRef.current as NodeJS.Timeout);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [validators.selectedNode]);

  // Verificar si el nodo seleccionado sigue siendo válido cuando cambie la lista de validadores
  useEffect(() => {
    if (!isSelectedNodeValid()) {
      console.log("El nodo seleccionado ya no es un validador activo, cambiando a un nodo válido...");
      selectValidNode();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [validators.minersList]);

  // Verificar si algún nodo ha sido expulsado recientemente
  const getExpelledNodes = () => {
    return config.nodes.filter(node => 
      node.accountAddress && !validators.minersList.some(validator => 
        validator.toLowerCase() === node.accountAddress.toLowerCase()
      )
    );
  };

  const handleSelectNode = (e: any) => {
    controller.abort();
    clearInterval(intervalRef.current as NodeJS.Timeout);
    setValidators({ ...validators, selectedNode: e.target.value });
  };

  // Función para verificar si el nodo seleccionado es válido
  const isSelectedNodeValid = () => {
    if (validators.minersList.length === 0) {
      return true; // Si no hay validadores cargados aún, asumir que es válido
    }
    
    const selectedNodeDetails = config.nodes.find(node => node.name === validators.selectedNode);
    if (!selectedNodeDetails || !selectedNodeDetails.accountAddress) {
      return true; // Si no tiene accountAddress, asumir que es válido para evitar errores
    }
    
    return validators.minersList.some(validator => 
      validator.toLowerCase() === selectedNodeDetails.accountAddress.toLowerCase()
    );
  };

  // Función para seleccionar automáticamente un nodo válido
  const selectValidNode = () => {
    if (validators.minersList.length === 0) {
      return; // No hacer nada si no hay validadores cargados
    }
    
    const validNode = config.nodes.find(node => 
      node.accountAddress && validators.minersList.some(validator => 
        validator.toLowerCase() === node.accountAddress.toLowerCase()
      )
    );
    
    if (validNode && validNode.name !== validators.selectedNode) {
      setValidators({ ...validators, selectedNode: validNode.name });
    }
  };
  if (typeof window !== "undefined" && loading) return null;
  if (isAuthEnabled && !session) {
    return <AccessDenied />;
  }
  return (
    <>
      <Container maxW={{ base: "container.sm", md: "container.xl" }}>
        <PageHeader
          title="Validators"
          config={config}
          selectNodeHandler={handleSelectNode}
          activeValidators={validators.minersList}
        />
        
        {/* Mostrar alerta para nodos expulsados */}
        {validators.minersList.length > 0 && getExpelledNodes().length > 0 && (
          <Alert status="warning" mt={4}>
            <AlertIcon />
            <Box>
              <AlertTitle>Nodos Expulsados Detectados</AlertTitle>
              <AlertDescription>
                Los siguientes nodos han sido expulsados de la red de validadores: {' '}
                {getExpelledNodes().map(node => node.name).join(', ')}. 
                Estos nodos ya no aparecen en el selector de nodos.
              </AlertDescription>
            </Box>
          </Alert>
        )}
        
        <Divider my={8} />
        <SimpleGrid columns={2} minChildWidth="600px">
          <ValidatorsAbout />
          <ValidatorsActive
            config={config}
            minersList={validators.minersList}
            selectedNode={validators.selectedNode}
            blacklistedValidators={validators.blacklistedValidators}
            nodeAddress={validators.nodeAddress}
          />
          <ValidatorsPropose
            config={config}
            selectedNode={validators.selectedNode}
            blacklistedValidators={validators.blacklistedValidators}
            nodeAddress={validators.nodeAddress}
          />
          <ValidatorsPending
            config={config}
            pendingList={validators.pendingList}
            selectedNode={validators.selectedNode}
          />
        </SimpleGrid>
      </Container>
    </>
  );
}

export const getServerSideProps: GetServerSideProps<{
  session: Session | null;
}> = async (context) => {
  const res = await configReader();
  const config: QuorumConfig = JSON.parse(res);
  const isAuthEnabled = process.env.DISABLE_AUTH === "false";
  return {
    props: {
      config,
      session: isAuthEnabled ? await getSession(context) : null,
    },
  };
};
