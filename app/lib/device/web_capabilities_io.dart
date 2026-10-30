/// Native builds reach MIDI and BLE through the platform packages, so both
/// transports are always available.
bool get isWebMidiSupported => true;

bool get isWebBluetoothSupported => true;
