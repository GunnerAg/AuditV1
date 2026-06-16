import { useState } from "react";
import { GetServerSideProps } from "next";
import type { Session } from "next-auth";
import { useSession, getSession } from "next-auth/react";
import AccessDenied from "../common/components/Misc/AccessDenied";
import { Container, SimpleGrid } from "@chakra-ui/react";
import PageHeader from "../common/components/Misc/PageHeader";
import WalletsTransferEth from "../common/components/Wallets/WalletsTransferEth";
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

export default function Wallets({ config }: IProps) {
  const isAuthEnabled = publicRuntimeConfig.DISABLE_AUTH === "false";
  const { data: session, status } = isAuthEnabled ? useSession() : { data: null, status: "unauthenticated" };
  const loading = isAuthEnabled && status === "loading";

  const [wallet, setWallet] = useState<IState>({
    selectedNode: config.nodes[0].name,
  });

  const handleSelectNode = (e: any) => {
    setWallet({ ...wallet, selectedNode: e.target.value });
  };
  if (typeof window !== "undefined" && loading) return null;
  if (isAuthEnabled && !session) {
    return <AccessDenied />;
  }
  return (
    <>
      <Container maxW={{ base: "container.sm", md: "container.sm" }}>
        <PageHeader
          title="Wallets"
          config={config}
          selectNodeHandler={handleSelectNode}
        />
        <SimpleGrid columns={1} minChildWidth="300px">
          <WalletsTransferEth
            config={config}
            selectedNode={wallet.selectedNode}
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
