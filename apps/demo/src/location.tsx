import * as Location from 'expo-location';
import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { ActionButton, ActionRow, DataRow, Field, Note, Panel, ResultPanel, useAsyncResult } from './ui';

function json(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

function validate(location: Location.LocationObject): void {
  const { coords, timestamp } = location;
  if (!Number.isFinite(coords.latitude) || Math.abs(coords.latitude) > 90
    || !Number.isFinite(coords.longitude) || Math.abs(coords.longitude) > 180 || !Number.isFinite(timestamp)) {
    throw new Error('定位结果包含无效的坐标或时间戳。');
  }

  for (const value of [coords.accuracy, coords.altitudeAccuracy, coords.speed, coords.heading]) {
    if (value !== null && (!Number.isFinite(value) || value < 0)) {
      throw new Error('精度、速度和方向必须为非负数或 null。');
    }
  }
  if (coords.altitude !== null && !Number.isFinite(coords.altitude)) {
    throw new Error('海拔必须为有限数值或 null。');
  }
}

function PermissionsCard() {
  const [permission, request, get] = Location.useForegroundPermissions();
  const [provider, setProvider] = useState<Location.LocationProviderStatus>();
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  const read = () => action.run(async () => {
    const [access, status, enabled] = await Promise.all([
      get(), Location.getProviderStatusAsync(), Location.hasServicesEnabledAsync(),
    ]);
    setProvider(status);

    return json({ permission: access, provider: status, enabled });
  });

  return (
    <Panel eyebrow="权限与服务" title="检查定位授权与系统开关">
      <DataRow label="前台权限" value={permission?.status ?? '加载中'} />
      <DataRow label="可再次询问" value={permission ? String(permission.canAskAgain) : '加载中'} />
      <DataRow label="定位服务" value={provider ? String(provider.locationServicesEnabled) : '尚未读取'} />
      <ActionRow>
        <ActionButton disabled={busy} label="读取权限与服务" onPress={() => void read()} testID="location-permissions-get" />
        <ActionButton disabled={busy} label="申请定位权限" onPress={() => void action.run(async () => json(await request()))} testID="location-permissions-request" tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function PositionCard() {
  const [age, setAge] = useState('0');
  const [position, setPosition] = useState<Location.LocationObject | null>();
  const [events, setEvents] = useState(0);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState('无');
  const watch = useRef<Location.LocationSubscription | null>(null);
  const generation = useRef(0);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => () => {
    generation.current += 1;
    watch.current?.remove();
    watch.current = null;
  }, []);

  const read = (cached: boolean) => action.run(async () => {
    const interval = Number(age);
    if (!cached && (!age.trim() || !Number.isFinite(interval) || interval < 0)) {
      throw new Error('缓存时限必须为非负毫秒数。');
    }

    const value = cached
      ? await Location.getLastKnownPositionAsync({ maxAge: 60_000, requiredAccuracy: 1000 })
      : await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High, timeInterval: interval });
    if (value) validate(value);
    setPosition(value);

    return json(value);
  });

  const start = () => action.run(async () => {
    const token = ++generation.current;
    watch.current?.remove();
    watch.current = null;
    setListening(false);
    setError('无');
    setEvents(0);

    const subscription = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.High, timeInterval: 1000, distanceInterval: 0 },
      (value) => {
        if (token !== generation.current) return;

        try {
          validate(value);
          setPosition(value);
          setEvents(count => count + 1);
        } catch (failure) {
          setError(String(failure));
        }
      },
      (reason) => {
        if (token === generation.current) setError(reason);
      }
    );
    if (token !== generation.current) {
      subscription.remove();
      return '页面已离开，订阅已释放。';
    }

    watch.current = subscription;
    setListening(true);

    return '已订阅；切换前后台或系统位置开关后，观察回调是否恢复。';
  });

  const stop = () => action.run(() => {
    generation.current += 1;
    watch.current?.remove();
    watch.current?.remove();
    watch.current = null;
    setListening(false);

    return '已连续调用两次 remove；回调计数应停止增加。';
  });

  return (
    <Panel eyebrow="位置" title="单次定位、缓存与持续订阅">
      <DataRow label="坐标" value={position ? `${position.coords.latitude}, ${position.coords.longitude}` : position === null ? '无符合条件的缓存' : '尚未读取'} />
      <DataRow label="精度（米）" value={position ? String(position.coords.accuracy) : '尚未读取'} />
      <DataRow label="时间戳（毫秒）" value={position ? String(position.timestamp) : '尚未读取'} />
      <DataRow label="订阅状态 / 回调次数" value={`${listening ? '已订阅' : '未订阅'} / ${events}`} />
      <DataRow label="订阅错误" value={error} />
      <Field label="单次定位可接受缓存（毫秒）" value={age} onChangeText={setAge} testID="location-cache-age" />
      <ActionRow>
        <ActionButton disabled={busy} label="获取当前位置" onPress={() => void read(false)} testID="location-current" />
        <ActionButton disabled={busy} label="读取缓存位置" onPress={() => void read(true)} testID="location-cached" tone="secondary" />
        <ActionButton disabled={busy || listening} label="订阅位置" onPress={() => void start()} testID="location-watch-start" tone="secondary" />
        <ActionButton disabled={busy || !listening} label="取消位置订阅" onPress={() => void stop()} testID="location-watch-stop" tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
      <Note>先授予权限并开启系统位置开关。单次定位缓存时限设为 0 获取新位置，设为 60000 后可观察一分钟内的时间戳复用。“读取缓存位置”还要求精度不超过 1000 米，不存在时返回 null。</Note>
    </Panel>
  );
}

function HeadingCard() {
  const [heading, setHeading] = useState<Location.LocationHeadingObject>();
  const [events, setEvents] = useState(0);
  const [listening, setListening] = useState(false);
  const [error, setError] = useState('无');
  const watch = useRef<Location.LocationSubscription | null>(null);
  const generation = useRef(0);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  useEffect(() => () => {
    generation.current += 1;
    watch.current?.remove();
    watch.current = null;
  }, []);

  const start = () => action.run(async () => {
    const token = ++generation.current;
    setEvents(0);
    setError('无');

    const subscription = await Location.watchHeadingAsync((value) => {
      if (token !== generation.current) return;
      if (!Number.isFinite(value.magHeading) || value.magHeading < 0 || value.magHeading >= 360
        || (value.trueHeading !== -1
          && (!Number.isFinite(value.trueHeading) || value.trueHeading < 0 || value.trueHeading >= 360))
        || !Number.isInteger(value.accuracy) || value.accuracy < 0 || value.accuracy > 3) {
        setError('方向结果不符合角度或准确度范围。');
        return;
      }

      setHeading(value);
      setEvents(count => count + 1);
    }, (reason) => {
      if (token === generation.current) setError(reason);
    });
    if (token !== generation.current) {
      subscription.remove();
      return '页面已离开，订阅已释放。';
    }

    watch.current = subscription;
    setListening(true);

    return '方向订阅已启动。';
  });

  const stop = () => action.run(() => {
    generation.current += 1;
    watch.current?.remove();
    watch.current?.remove();
    watch.current = null;
    setListening(false);

    return '已连续调用两次 remove；方向回调应停止。';
  });

  return (
    <Panel eyebrow="方向" title="观察磁北与真北">
      <DataRow label="磁北 / 真北" value={heading ? `${heading.magHeading.toFixed(2)}° / ${heading.trueHeading === -1 ? '不可用' : `${heading.trueHeading.toFixed(2)}°`}` : '尚未读取'} />
      <DataRow label="准确度 / 回调次数" value={`${heading?.accuracy ?? '未知'} / ${events}`} />
      <DataRow label="订阅状态" value={listening ? '已订阅' : '未订阅'} />
      <DataRow label="订阅错误" value={error} />
      <ActionRow>
        <ActionButton disabled={busy || listening} label="订阅方向" onPress={() => void start()} testID="location-heading-start" />
        <ActionButton disabled={busy || !listening} label="取消方向订阅" onPress={() => void stop()} testID="location-heading-stop" tone="secondary" />
      </ActionRow>
      <ResultPanel state={action.state} />
      <Note>先授予权限并开启系统位置开关；真北还需要可用位置。关闭位置或收回权限应报告错误并暂停回调，恢复后继续。模拟器可能没有方向传感器；离开此页会释放订阅。</Note>
    </Panel>
  );
}

function GeocodeCard() {
  const [address, setAddress] = useState('北京市海淀区中关村');
  const [latitude, setLatitude] = useState('39.984');
  const [longitude, setLongitude] = useState('116.307');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  const reverse = () => action.run(async () => {
    if (!latitude.trim() || !longitude.trim()) throw new Error('请输入经纬度。');
    const point = { latitude: Number(latitude), longitude: Number(longitude) };
    if (!Number.isFinite(point.latitude) || Math.abs(point.latitude) > 90
      || !Number.isFinite(point.longitude) || Math.abs(point.longitude) > 180) {
      throw new Error('经纬度必须为有效的 WGS-84 坐标。');
    }

    return json(await Location.reverseGeocodeAsync(point));
  });

  return (
    <Panel eyebrow="地理编码" title="地址与坐标转换">
      <Field label="地址" value={address} onChangeText={setAddress} testID="location-address" />
      <ActionButton disabled={busy || !address.trim()} label="地址转坐标" onPress={() => void action.run(async () => json(await Location.geocodeAsync(address)))} testID="location-geocode" />
      <Field label="纬度" value={latitude} onChangeText={setLatitude} testID="location-latitude" />
      <Field label="经度" value={longitude} onChangeText={setLongitude} testID="location-longitude" />
      <ActionButton disabled={busy} label="坐标转地址" onPress={() => void reverse()} testID="location-reverse-geocode" tone="secondary" />
      <ResultPanel state={action.state} />
      <Note>使用系统地址服务，需定位权限。无匹配结果时可能返回空数组，服务不可用时显示原生错误。</Note>
    </Panel>
  );
}

function ChecksCard() {
  const action = useAsyncResult();
  const harmony = (Platform.OS as string) === 'harmony';

  const verify = () => action.run(async () => {
    const checks: [string, () => Promise<unknown>, string][] = [
      ['越界坐标', () => Location.reverseGeocodeAsync({ latitude: 91, longitude: 0 }), 'ERR_LOCATION_INVALID_ARGUMENT'],
      ['无效精度', () => Location.getCurrentPositionAsync({ accuracy: 0 as Location.Accuracy }), 'ERR_LOCATION_INVALID_ARGUMENT'],
      ['负缓存时限', () => Location.getLastKnownPositionAsync({ maxAge: -1 }), 'ERR_LOCATION_INVALID_ARGUMENT'],
      ['后台定位', () => Location.startLocationUpdatesAsync('expo-location-demo'), 'ERR_LOCATION_BACKGROUND_UNAVAILABLE'],
      ['地理围栏', () => Location.startGeofencingAsync('expo-location-demo', [{ identifier: 'demo', latitude: 0, longitude: 0, radius: 100 }]), 'ERR_LOCATION_GEOFENCING_UNAVAILABLE'],
      ['停止未注册任务', () => Location.stopLocationUpdatesAsync('expo-location-demo'), 'ERR_TASK_NOT_FOUND'],
    ];
    const rows: string[] = [];

    for (const [label, run, expected] of checks) {
      let code: string | undefined;
      try {
        await run();
      } catch (error) {
        code = (error as { code?: string }).code;
      }
      if (code !== expected) throw new Error(`${label}：预期 ${expected}，实际 ${code ?? '未拒绝或未提供错误码'}。`);

      rows.push(`${label}：${code}`);
    }

    const [permission, locations, regions] = await Promise.all([
      Location.getBackgroundPermissionsAsync(),
      Location.hasStartedLocationUpdatesAsync('expo-location-demo'),
      Location.hasStartedGeofencingAsync('expo-location-demo'),
    ]);
    if (permission.status !== 'denied' || permission.canAskAgain || locations || regions) {
      throw new Error('当前 HarmonyOS 移植不应声明已支持后台定位或地理围栏。');
    }

    return `${rows.join('\n')}\n后台权限与任务查询：通过`;
  });

  return (
    <Panel eyebrow="接口校验" title="检查参数边界与未支持能力">
      <Note>这些检查针对当前 HarmonyOS 移植的错误码，不会申请后台权限或创建后台任务。其他平台请使用上方通用卡片。</Note>
      <ActionButton disabled={!harmony || action.state.phase === 'running'} label="校验参数与错误码" onPress={() => void verify()} testID="location-verify" />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

export function LocationDemo() {
  return (
    <>
      <PermissionsCard />
      <PositionCard />
      <HeadingCard />
      <GeocodeCard />
      <ChecksCard />
    </>
  );
}
