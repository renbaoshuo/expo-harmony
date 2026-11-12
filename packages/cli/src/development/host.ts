/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import os from 'node:os';

import { HarmonyCliError } from '../errors';
import { requireFromExpoCli } from '../expo';

export function parseHostOption(host?: string): string | undefined {
  if (host !== undefined && !/^[A-Za-z0-9.-]+$/.test(host)) {
    throw new HarmonyCliError(
      'ERR_HARMONY_CONFIG_INVALID',
      '--host must be a hostname or IPv4 address without a port or scheme.',
      { operation: 'parse-arguments' }
    );
  }

  return host;
}

function interfacePriority(name: string, info: os.NetworkInterfaceInfo): number {
  // Interface names alone cannot identify every virtual adapter (especially on Windows).
  const virtual = /^(utun|tun|tap|wg|ppp|ipsec|vmnet|vboxnet|virbr|docker|br-|bridge\d|veth|tailscale|zt)|virtual|vmware|vpn/i.test(name)
    || /^(00:00:00:00:00:00|00:05:69:|00:0c:29:|00:1c:14:|00:50:56:|08:00:27:|00:15:5d:)/i.test(info.mac)
    || /^198\.(18|19)\./.test(info.address);

  return Number(virtual) + (info.address.startsWith('169.254.') ? 2 : 0);
}

export async function resolveDevelopmentHostAsync(root: string, hostname?: string): Promise<string> {
  const override = hostname || process.env.REACT_NATIVE_PACKAGER_HOSTNAME;
  if (override) {
    if (!/^[A-Za-z0-9.-]+$/.test(override)) {
      throw new HarmonyCliError(
        'ERR_HARMONY_MANIFEST_HOST',
        'Harmony development requires an HTTP LAN hostname or IPv4 address.',
        { operation: 'development-manifest' }
      );
    }

    return override;
  }

  const candidates = Object.entries(os.networkInterfaces()).flatMap(([name, addresses]) =>
    (addresses || [])
      .filter(info => info.family === 'IPv4' && !info.internal)
      .map(info => ({ address: info.address, priority: interfacePriority(name, info) }))
  ).sort((a, b) => a.priority - b.priority);

  if (!candidates.length) return '127.0.0.1';

  const preferred = candidates.filter(candidate => candidate.priority === candidates[0].priority);
  if (preferred.length > 1) {
    // Use Expo's route discovery to choose between equally suitable interfaces,
    // but do not let a VPN default route displace an available LAN interface.
    const { getGatewayAsync } = requireFromExpoCli(root)('./build/src/utils/ip');
    const gateway = await getGatewayAsync();
    if (preferred.some(candidate => candidate.address === gateway.address)) return gateway.address;
  }

  return preferred[0].address;
}
