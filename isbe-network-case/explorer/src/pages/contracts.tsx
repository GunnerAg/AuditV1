import { useState, useRef } from "react";
import { GetServerSideProps } from "next";
import type { Session } from "next-auth";
import { useSession, getSession } from "next-auth/react";
import AccessDenied from "../common/components/Misc/AccessDenied";
import { Container } from "@chakra-ui/react";
import PageHeader from "../common/components/Misc/PageHeader";
import ContractsIndex from "../common/components/Contracts/ContractsIndex";
import { QuorumConfig } from "../common/types/QuorumConfig";
import { configReader } from "../common/lib/getConfig";
import getConfig from "next/config";
const { publicRuntimeConfig } = getConfig();

interface IState {
  selectedNode: string;
}

interface IProps {
  config: QuorumConfig;
}

export default function Contracts({ config }: IProps) {
  const isAuthEnabled = publicRuntimeConfig.DISABLE_AUTH === "false";
  const { data: session, status } = isAuthEnabled ? useSession() : { data: null, status: "unauthenticated" };
  const loading = isAuthEnabled && status === "loading";

  const intervalRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [contracts, setContracts] = useState<IState>({
    selectedNode: config.nodes[0].name,
  });

  const handleSelectNode = (e: any) => {
    clearInterval(intervalRef.current as NodeJS.Timeout);
    setContracts({ ...contracts, selectedNode: e.target.value });
  };
  if (typeof window !== "undefined" && loading) return null;
  if (isAuthEnabled && !session) {
    return <AccessDenied />;
  }
  return (
    <>
      <Container maxW={{ base: "container.sm", md: "container.xl" }}>
        <PageHeader
          title="Contracts"
          config={config}
          selectNodeHandler={handleSelectNode}
        />
        <ContractsIndex config={config} selectedNode={contracts.selectedNode} />
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
