/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Location from 'expo-location';
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { Platform } from 'react-native';

import { json } from '../format';
import { ActionButton, ActionRow, DataRow, Field, Panel, ResultPanel, useAsyncResult } from '../ui';
import { GEOFENCING_TASK, LOCATION_TASK, getLocationEvent, subscribeToLocationEvents } from './location/tasks';

const ACCURACIES = [
  [Location.Accuracy.Lowest, '最低'],
  [Location.Accuracy.Low, '低'],
  [Location.Accuracy.Balanced, '均衡'],
  [Location.Accuracy.High, '高'],
  [Location.Accuracy.Highest, '最高'],
  [Location.Accuracy.BestForNavigation, '导航'],
] as const;

function optionalNumber(text: string, name: string) {
  if (!text.trim()) return undefined;
  const value = Number(text);
  if (!Number.isFinite(value) || value < 0) throw new Error(`${name}须为非负数`);
  return value;
}

function PermissionsCard() {
  const [foreground, requestForeground, getForeground] = Location.useForegroundPermissions();
  const [background, requestBackground, getBackground] = Location.useBackgroundPermissions({ get: false });
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';
  const operations = [
    ['读取前台权限', getForeground, 'location-permissions-get'],
    ['申请前台权限', requestForeground, 'location-permissions-request'],
    ['读取后台权限', getBackground],
    ['申请后台权限', requestBackground],
    ['读取定位服务状态', Location.getProviderStatusAsync],
    ['查看定位服务是否开启', Location.hasServicesEnabledAsync],
    ['检查后台定位可用性', Location.isBackgroundLocationAvailableAsync],
  ] as const;

  return (
    <Panel title="定位权限与服务">
      <DataRow label="前台权限" value={foreground?.status ?? '加载中'} />
      <DataRow label="后台权限" value={background?.status ?? '尚未读取'} />
      <ActionRow>
        {operations.map(([label, run, testID]) => (
          <ActionButton key={label} disabled={busy} label={label} onPress={() => void action.run(async () => json(await run()))} testID={testID} tone="secondary" />
        ))}
        {Platform.OS === 'android'
          ? (
              <ActionButton
                disabled={busy}
                label="开启网络定位"
                onPress={() => void action.run(async () => {
                  await Location.enableNetworkProviderAsync();
                  return '已开启网络定位';
                })}
              />
            )
          : null}
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function AccuracyOptions({ value, onChange }: {
  value: Location.Accuracy | undefined;
  onChange: (value: Location.Accuracy | undefined) => void;
}) {
  return (
    <>
      <DataRow label="定位精度" value={ACCURACIES.find(([accuracy]) => accuracy === value)?.[1] ?? '默认'} />
      <ActionRow>
        <ActionButton label="默认" onPress={() => onChange(undefined)} tone={value === undefined ? 'primary' : 'secondary'} />
        {ACCURACIES.map(([accuracy, label]) => (
          <ActionButton key={accuracy} label={label} onPress={() => onChange(accuracy)} tone={value === accuracy ? 'primary' : 'secondary'} />
        ))}
      </ActionRow>
    </>
  );
}

type StartWatch<T> = (
  onValue: (value: T) => void,
  onError: Location.LocationErrorCallback
) => Promise<Location.LocationSubscription>;

function useLocationWatch<T>() {
  const [sample, setSample] = useState<T>();
  const [error, setError] = useState<string>();
  const [active, setActive] = useState(false);
  const subscription = useRef<Location.LocationSubscription | null>(null);
  const generation = useRef(0);
  const action = useAsyncResult();

  useEffect(() => () => {
    generation.current += 1;
    subscription.current?.remove();
    subscription.current = null;
  }, []);

  const start = (watch: StartWatch<T>) => action.run(async () => {
    const token = ++generation.current;
    subscription.current?.remove();
    subscription.current = null;
    setSample(undefined);
    setError(undefined);
    const next = await watch(
      (value) => {
        if (token === generation.current) setSample(value);
      },
      (reason) => {
        if (token === generation.current) setError(reason);
      }
    );
    if (token === generation.current) {
      subscription.current = next;
      setActive(true);
    } else {
      next.remove();
    }
    return '已开始监听';
  });

  const stop = () => action.run(() => {
    generation.current += 1;
    subscription.current?.remove();
    subscription.current = null;
    setActive(false);
    return '已停止监听';
  });

  return { action, active, error, sample, start, stop };
}

function PositionCard() {
  const [accuracy, setAccuracy] = useState<Location.Accuracy>();
  const [interval, setInterval] = useState('0');
  const [distance, setDistance] = useState('');
  const watch = useLocationWatch<Location.LocationObject>();
  const busy = watch.action.state.phase === 'running';

  const options = (): Location.LocationOptions => ({
    accuracy,
    timeInterval: optionalNumber(interval, '时间间隔'),
  });

  return (
    <Panel title="当前位置">
      <AccuracyOptions value={accuracy} onChange={setAccuracy} />
      <Field label="时间间隔（毫秒）" value={interval} onChangeText={setInterval} keyboardType="number-pad" />
      <ActionButton disabled={busy} label="获取当前位置" onPress={() => void watch.action.run(async () => json(await Location.getCurrentPositionAsync(options())))} testID="location-current" />
      <Field label="订阅更新距离（米）" value={distance} onChangeText={setDistance} keyboardType="decimal-pad" />
      <ActionRow>
        <ActionButton
          disabled={busy || watch.active}
          label="订阅位置"
          onPress={() => void watch.start((onValue, onError) => Location.watchPositionAsync({
            ...options(),
            distanceInterval: optionalNumber(distance, '更新距离'),
          }, onValue, onError))}
          testID="location-watch-start"
        />
        <ActionButton disabled={busy || !watch.active} label="取消位置订阅" onPress={() => void watch.stop()} testID="location-watch-stop" tone="secondary" />
      </ActionRow>
      {watch.sample ? <DataRow label="最近一次更新" value={json(watch.sample)} /> : null}
      {watch.error ? <DataRow label="订阅错误" value={watch.error} /> : null}
      <ResultPanel state={watch.action.state} />
    </Panel>
  );
}

function CachedPositionCard() {
  const [age, setAge] = useState('60000');
  const [accuracy, setAccuracy] = useState('1000');
  const action = useAsyncResult();
  return (
    <Panel title="缓存位置">
      <Field label="缓存时长上限（毫秒）" value={age} onChangeText={setAge} keyboardType="number-pad" testID="location-cache-age" />
      <Field label="精度半径上限（米）" value={accuracy} onChangeText={setAccuracy} keyboardType="decimal-pad" />
      <ActionButton
        disabled={action.state.phase === 'running'}
        label="读取缓存位置"
        onPress={() => void action.run(async () => json(await Location.getLastKnownPositionAsync({
          maxAge: optionalNumber(age, '缓存时长'),
          requiredAccuracy: optionalNumber(accuracy, '精度半径'),
        })))}
        testID="location-cached"
      />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function HeadingCard() {
  const watch = useLocationWatch<Location.LocationHeadingObject>();
  const busy = watch.action.state.phase === 'running';

  return (
    <Panel title="设备方向">
      <ActionRow>
        <ActionButton disabled={busy} label="读取当前方向" onPress={() => void watch.action.run(async () => json(await Location.getHeadingAsync()))} />
        <ActionButton disabled={busy || watch.active} label="订阅方向" onPress={() => void watch.start(Location.watchHeadingAsync)} testID="location-heading-start" />
        <ActionButton disabled={busy || !watch.active} label="取消方向订阅" onPress={() => void watch.stop()} testID="location-heading-stop" tone="secondary" />
      </ActionRow>
      {watch.sample ? <DataRow label="最近一次更新" value={json(watch.sample)} /> : null}
      {watch.error ? <DataRow label="订阅错误" value={watch.error} /> : null}
      <ResultPanel state={watch.action.state} />
    </Panel>
  );
}

function GeocodeCard() {
  const [address, setAddress] = useState('北京市海淀区中关村');
  const [latitude, setLatitude] = useState('39.984');
  const [longitude, setLongitude] = useState('116.307');
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="地理编码">
      <Field label="地址" value={address} onChangeText={setAddress} testID="location-address" />
      <ActionButton disabled={busy || !address.trim()} label="地址转坐标" onPress={() => void action.run(async () => json(await Location.geocodeAsync(address)))} testID="location-geocode" />
      <Field label="纬度" value={latitude} onChangeText={setLatitude} keyboardType="numbers-and-punctuation" testID="location-latitude" />
      <Field label="经度" value={longitude} onChangeText={setLongitude} keyboardType="numbers-and-punctuation" testID="location-longitude" />
      <ActionButton
        disabled={busy || !latitude.trim() || !longitude.trim()}
        label="坐标转地址"
        onPress={() => void action.run(async () => json(await Location.reverseGeocodeAsync({
          latitude: Number(latitude),
          longitude: Number(longitude),
        })))}
        testID="location-reverse-geocode"
      />
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function BackgroundLocationCard() {
  const [accuracy, setAccuracy] = useState<Location.Accuracy>();
  const [interval, setInterval] = useState('');
  const [distance, setDistance] = useState('');
  const [deferredDistance, setDeferredDistance] = useState('');
  const [deferredInterval, setDeferredInterval] = useState('');
  const [deferredTimeout, setDeferredTimeout] = useState('');
  const event = useSyncExternalStore(subscribeToLocationEvents, () => getLocationEvent(LOCATION_TASK));
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="后台定位">
      <AccuracyOptions value={accuracy} onChange={setAccuracy} />
      <Field label="更新间隔（毫秒）" value={interval} onChangeText={setInterval} keyboardType="number-pad" />
      <Field label="更新距离（米）" value={distance} onChangeText={setDistance} keyboardType="decimal-pad" />
      <Field label="批量更新间隔（毫秒）" value={deferredInterval} onChangeText={setDeferredInterval} keyboardType="number-pad" />
      <Field label="批量更新距离（米）" value={deferredDistance} onChangeText={setDeferredDistance} keyboardType="decimal-pad" />
      <Field label="批量更新超时（毫秒）" value={deferredTimeout} onChangeText={setDeferredTimeout} keyboardType="number-pad" />
      <ActionRow>
        <ActionButton
          label="开始后台定位"
          disabled={busy}
          onPress={() => void action.run(async () => {
            await Location.startLocationUpdatesAsync(LOCATION_TASK, {
              accuracy,
              timeInterval: optionalNumber(interval, '更新间隔'),
              distanceInterval: optionalNumber(distance, '更新距离'),
              deferredUpdatesInterval: optionalNumber(deferredInterval, '批量更新间隔'),
              deferredUpdatesDistance: optionalNumber(deferredDistance, '批量更新距离'),
              deferredUpdatesTimeout: optionalNumber(deferredTimeout, '批量更新超时'),
            });
            return '已注册后台定位';
          })}
        />
        <ActionButton label="读取注册状态" disabled={busy} onPress={() => void action.run(async () => json(await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK)))} tone="secondary" />
        <ActionButton
          label="停止后台定位"
          disabled={busy}
          onPress={() => void action.run(async () => {
            await Location.stopLocationUpdatesAsync(LOCATION_TASK);
            return '已停止后台定位';
          })}
          tone="secondary"
        />
      </ActionRow>
      {event ? <DataRow label="最近一次更新" value={json(event)} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function GeofencingCard() {
  const [regions, setRegions] = useState(() => json([{
    identifier: 'demo',
    latitude: 39.984,
    longitude: 116.307,
    radius: 100,
    notifyOnEnter: true,
    notifyOnExit: true,
  }] satisfies Location.LocationRegion[]));
  const event = useSyncExternalStore(subscribeToLocationEvents, () => getLocationEvent(GEOFENCING_TASK));
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="地理围栏">
      <Field label="围栏列表（JSON）" multiline value={regions} onChangeText={setRegions} />
      <ActionRow>
        <ActionButton
          label="注册围栏"
          disabled={busy}
          onPress={() => void action.run(async () => {
            await Location.startGeofencingAsync(GEOFENCING_TASK, JSON.parse(regions) as Location.LocationRegion[]);
            return '已注册围栏';
          })}
        />
        <ActionButton label="读取注册状态" disabled={busy} onPress={() => void action.run(async () => json(await Location.hasStartedGeofencingAsync(GEOFENCING_TASK)))} tone="secondary" />
        <ActionButton
          label="移除围栏"
          disabled={busy}
          onPress={() => void action.run(async () => {
            await Location.stopGeofencingAsync(GEOFENCING_TASK);
            return '已移除围栏';
          })}
          tone="secondary"
        />
      </ActionRow>
      {event ? <DataRow label="最近一次围栏事件" value={json(event)} /> : null}
      <ResultPanel state={action.state} />
    </Panel>
  );
}

function MotionActivityCard() {
  const [permission, request, get] = Location.useMotionActivityPermissions();
  const watch = useLocationWatch<Location.MotionActivityObject>();
  const busy = watch.action.state.phase === 'running';

  return (
    <Panel title="运动状态">
      <DataRow label="运动识别权限" value={permission?.status ?? '加载中'} />
      <ActionRow>
        <ActionButton label="读取权限" disabled={busy} onPress={() => void watch.action.run(async () => json(await get()))} tone="secondary" />
        <ActionButton label="申请权限" disabled={busy} onPress={() => void watch.action.run(async () => json(await request()))} />
        <ActionButton label="读取运动状态" disabled={busy} onPress={() => void watch.action.run(async () => json(await Location.getMotionActivityAsync()))} />
        <ActionButton label="订阅运动状态" disabled={busy || watch.active} onPress={() => void watch.start(Location.watchMotionActivityAsync)} />
        <ActionButton label="取消运动订阅" disabled={busy || !watch.active} onPress={() => void watch.stop()} tone="secondary" />
      </ActionRow>
      {watch.sample ? <DataRow label="最近一次更新" value={json(watch.sample)} /> : null}
      {watch.error ? <DataRow label="订阅错误" value={watch.error} /> : null}
      <ResultPanel state={watch.action.state} />
    </Panel>
  );
}

function GeolocationPolyfillCard() {
  const [highAccuracy, setHighAccuracy] = useState(false);
  const action = useAsyncResult();
  const busy = action.state.phase === 'running';

  return (
    <Panel title="Geolocation 兼容接口">
      <ActionRow>
        <ActionButton label="均衡精度" onPress={() => setHighAccuracy(false)} tone={highAccuracy ? 'secondary' : 'primary'} />
        <ActionButton label="高精度" onPress={() => setHighAccuracy(true)} tone={highAccuracy ? 'primary' : 'secondary'} />
      </ActionRow>
      <ActionRow>
        <ActionButton
          label="安装 Geolocation 兼容接口"
          disabled={busy}
          onPress={() => void action.run(() => {
            Location.installWebGeolocationPolyfill();
            return json({ geolocation: typeof navigator.geolocation });
          })}
        />
        <ActionButton
          label="通过 Geolocation 获取位置"
          disabled={busy || !globalThis.navigator?.geolocation}
          onPress={() => void action.run(() => new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(
              value => resolve(json(value)), reject, { enableHighAccuracy: highAccuracy }
            );
          }))}
          tone="secondary"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

export function LocationDemo() {
  return (
    <>
      <PermissionsCard />
      <PositionCard />
      <CachedPositionCard />
      <HeadingCard />
      <GeocodeCard />
      {Platform.OS === 'ios' || Platform.OS === 'android' ? <MotionActivityCard /> : null}
      {Platform.OS !== 'web'
        ? (
            <>
              <BackgroundLocationCard />
              <GeofencingCard />
            </>
          )
        : null}
      <GeolocationPolyfillCard />
    </>
  );
}
