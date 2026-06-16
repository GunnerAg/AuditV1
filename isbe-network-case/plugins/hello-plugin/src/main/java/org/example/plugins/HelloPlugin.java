package org.example.plugins;

import org.hyperledger.besu.plugin.BesuPlugin;
import org.hyperledger.besu.plugin.ServiceManager;

public class HelloPlugin implements BesuPlugin {

    @Override
    public void register(ServiceManager serviceManager) {
        System.out.println("HelloPlugin registrado!");
    }

    @Override
    public void start() {
        System.out.println("HelloPlugin arrancado");
    }

    @Override
    public void stop() {
        System.out.println("HelloPlugin detenido");
    }
}
