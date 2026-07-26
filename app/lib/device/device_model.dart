/// The Sonicake hardware model the app is talking to. [smartBox] is the newer,
/// superset device; [pocketMaster] is the older subset. [unknown] means we
/// haven't (or can't) identify the device — treated as full-capability so we
/// never hide effects the device might actually support (fail-open).
enum DeviceModel { pocketMaster, smartBox, unknown }
