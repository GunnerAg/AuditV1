import type { AppProps } from "next/app";
import { useState } from "react";
import { SessionProvider } from "next-auth/react";
import { ChakraProvider } from "@chakra-ui/react";
import { extendTheme } from "@chakra-ui/react";
import { createBreakpoints } from "@chakra-ui/theme-tools";
import "../../styles/globals.css";
import Layout from "../common/components/Misc/Layout";
import getConfig from "next/config";
const { publicRuntimeConfig } = getConfig();

function MyApp({ Component, pageProps, router }: AppProps) {
  const breakpoints = createBreakpoints({
    sm: "320px",
    md: "850px",
    lg: "960px",
    xl: "1200px",
    "2xl": "1536px",
  });
  const theme = extendTheme({
    breakpoints,
  });

  const isAuthEnabled = publicRuntimeConfig.DISABLE_AUTH === "false";

  const content = (
    <ChakraProvider theme={theme}>
      <title>Quorum Explorer</title>
      <Layout>
        <Component {...pageProps} />
      </Layout>
    </ChakraProvider>
  );

  return isAuthEnabled ? (
    <SessionProvider
      // Provider options are not required but can be useful in situations where
      // you have a short session maxAge time. Shown here with default values.
      session={pageProps.session}
      refetchInterval={10}
      refetchOnWindowFocus={true}
    >
      {content}
    </SessionProvider>
  ) : (
    content
  );
}

export default MyApp;
