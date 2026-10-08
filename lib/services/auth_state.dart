import 'package:flutter/material.dart';

import 'api_service.dart';
import 'token_store.dart';

class AuthState extends ChangeNotifier {
  AuthState() {
    TokenStore.instance.addListener(_sessionChanged);
  }
  void _sessionChanged() {
    if (!TokenStore.instance.hasSession) {
      _role = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    TokenStore.instance.removeListener(_sessionChanged);
    super.dispose();
  }

  String? _role;
  String? get role => _role;

  bool get isLoggedIn => _role != null;

  void restore(String? role) {
    _role = role;
  }

  void login(String role) {
    if (!TokenStore.instance.hasSession) return;
    _role = role;
    notifyListeners();
  }

  Future<void> logout({bool allDevices = false}) async {
    await ApiService.logout(allDevices: allDevices);
  }
}
