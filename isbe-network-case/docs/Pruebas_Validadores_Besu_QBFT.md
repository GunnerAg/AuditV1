# Informe de Pruebas sobre Validadores QBFT (Besu)

## 1. Número mínimo de validadores

-   **En QBFT aplica la regla 3f + 1:**

    -   Para tolerar f fallos (nodos caídos o maliciosos) se
        necesitan 3f + 1 validadores activos.

    -   La mayoría necesaria para validar bloques es siempre de 2/3 de
        los validadores.

-   La red debe arrancar obligatoriamente con al menos 3 validadores.

    -   El bootnode puede ser validador o no, según la configuración.

## 2. Pruebas de parada y recuperación

-   Parada de nodos

    -   Si un nodo validador se detiene y se baja de los 3 validadores
        mínimos, la red se detiene.

    -   El mecanismo RoundChangeManager entra en acción, reiniciando
        rondas sin poder avanzar.

-   Recuperación

    -   Cuando el nodo detenido se reinicia, necesita sincronizarse con
        el resto.

    -   Riesgo: el tiempo de sincronización puede ser proporcional al
        tiempo que los otros validadores han seguido incrementando sus
        rondas en su ausencia.

    -   Resultado esperado: la red vuelve a estabilizarse cuando el nodo
        se pone al día.

## 3. Información de validadores

**3.1 Vía comandos**

-   Comprobar validadores activos en la red:

```bash
curl -s -X POST --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' -H "Content-Type: application/json" http://localhost:8545 | jq
```

-   Verificar el extraData de cada bloque (ID de red, validadores,
    firmas y flag de consenso):

```bash
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' -H "Content-Type: application/json" http://localhost:8545 | jq '.result.extraData'
```

-   Exportar extraData de un bloque específico al archivo `extradata.txt` 

```bash
curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["160", false],"id":1}' | jq -r '.result.extraData' > extradata.txt
```

-   Decodificar el contenido de `extradata.txt` usando la imagen Docker de Besu:

```bash
docker run --rm -v "$(pwd):/opt/besu/data" hyperledger/besu:latest rlp decode --from=/opt/besu/data/extradata.txt --type=QBFT_EXTRA_DATA
```


**3.2 Vía Frontal Web con explorador de bloques ligero**

El Quorum Explorer permite gestionar validadores de forma visual:

-   Visualización en tiempo real

    -   Listado dinámico de direcciones validadoras activas.

    -   Estado: activo, propuesto, pendiente de salida.

-   Gestión de validadores vía votaciones (API
    qbft_proposeValidatorVote)

    -   Proponer nuevo validador → se solicita dirección del nodo
        candidato.

    -   Proponer expulsión de validador → voto para eliminarlo.

    -   Los cambios se registran en blockchain y se consolidan en el
        próximo epoch block.

-   Auditoría y trazabilidad

    -   Cada propuesta queda almacenada y visible en el explorador.

    -   Se puede consultar en qué bloque fue aplicado el cambio.

3.3 Información de nodos validadores

Se puede ejecutar el script nodeInfo.sh en cada contenedor/nodo para
identificar:

-   Enode (dirección de red p2p).

-   Public key.

-   Address de validador (0x\...).

Ejemplo:

**bash nodeInfo.sh**

Esto facilita mapear qué validador corresponde a cada nodo físico o
contenedor.

4\. Epoch blocks

-   Cada cierto número de bloques (epochLength) Besu genera un epoch
    block.

-   En ese bloque:

    -   El extraData incluye la lista completa de validadores activos en
        ese momento.

-   Función principal:

    -   Consolidación periódica de validadores.

    -   Facilita la sincronización de nodos que se conectan tarde o se
        reinician.

Se ha comprobado como al llegar al Quorum minimo de 2/3 se aplican los
cambios tan pronto como se sincronizen los nodos en el próximo bloque.
