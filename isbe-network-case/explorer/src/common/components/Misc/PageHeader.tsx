import {
  Heading,
  Container,
  HStack,
  Box,
  Flex,
  Select,
} from "@chakra-ui/react";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { IconProp } from "@fortawesome/fontawesome-svg-core";
import { faSlidersH } from "@fortawesome/free-solid-svg-icons";
import { QuorumConfig } from "../../types/QuorumConfig";
import { getNodeKeys } from "../../lib/quorumConfig";
import { motion } from "framer-motion";
const MotionContainer = motion(Container);

interface IProps {
  title: string;
  config: QuorumConfig;
  selectNodeHandler: any;
  isLoading?: boolean;
  activeValidators?: string[]; // Lista de validadores activos
}

export default function PageHeader(props: IProps) {
  // Filtrar nodos basándose en validadores activos
  const getAvailableNodes = (): string[] => {
    if (!props.activeValidators || props.activeValidators.length === 0) {
      // Si no hay validadores activos disponibles, mostrar todos los nodos
      return getNodeKeys(props.config);
    }
    
    // Filtrar solo los nodos que son validadores activos
    const activeNodes = props.config.nodes
      .filter(node => 
        node.accountAddress && props.activeValidators!.some(validator => 
          validator.toLowerCase() === node.accountAddress.toLowerCase()
        )
      )
      .map(node => node.name);
    
    // Si no hay nodos activos, mostrar al menos el primer nodo como fallback
    return activeNodes.length > 0 ? activeNodes : [props.config.nodes[0].name];
  };

  const availableNodes: string[] = getAvailableNodes();

  return (
    <>
      <MotionContainer
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.2 }}
        maxW={{ base: "container.sm", md: "container.xl" }}
      >
        <Flex
          flexDirection="row"
          justifyContent="space-between"
          alignItems="center"
          mt={5}
        >
          <Box>
            <Heading as="h1" size="lg" textAlign="center">
              {props.title}
            </Heading>
          </Box>
          <Box alignItems="center">
            <HStack>
              <FontAwesomeIcon icon={faSlidersH as IconProp} fontSize="lg" />
              <Select
                size="lg"
                variant="filled"
                onChange={props.selectNodeHandler}
              >
                {availableNodes.map((node) => (
                  <option key={node} value={node}>
                    {node}
                  </option>
                ))}
              </Select>
            </HStack>
          </Box>
        </Flex>
      </MotionContainer>
    </>
  );
}
