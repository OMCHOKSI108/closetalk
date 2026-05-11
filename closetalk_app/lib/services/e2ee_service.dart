import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class E2EEService {
  Future<SimpleKeyPair> generateKeyPair() {
    return X25519().newKeyPair();
  }

  Future<SimplePublicKey> extractPublicKey(SimpleKeyPair keyPair) {
    return keyPair.extractPublicKey();
  }

  Future<SecretKey> computeSharedSecret({
    required SimpleKeyPair myKeyPair,
    required SimplePublicKey remotePublicKey,
  }) async {
    return X25519().sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: remotePublicKey,
    );
  }

  Future<SecretKey> deriveSessionKey(SecretKey sharedSecret) async {
    final sharedBytes = await sharedSecret.extractBytes();
    final hash = await Sha256().hash(sharedBytes);
    return SecretKey(hash.bytes);
  }

  Future<String> encryptMessage({
    required String plaintext,
    required SecretKey sessionKey,
  }) async {
    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: sessionKey,
    );
    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(combined);
  }

  Future<String> decryptMessage({
    required String encryptedBase64,
    required SecretKey sessionKey,
  }) async {
    final combined = base64Decode(encryptedBase64);
    final aesGcm = AesGcm.with256bits();
    final nonceLength = aesGcm.nonceLength;
    final macLength = 16;
    final nonce = combined.sublist(0, nonceLength);
    final cipherText = combined.sublist(nonceLength, combined.length - macLength);
    final macBytes = combined.sublist(combined.length - macLength);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    final plaintext = await aesGcm.decrypt(
      secretBox,
      secretKey: sessionKey,
    );
    return utf8.decode(plaintext);
  }
}
