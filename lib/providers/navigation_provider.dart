import 'package:flutter/material.dart';

class MainNavigationProvider extends ChangeNotifier {
  int _currentIndex = 0;
  bool _isImmersive = false;

  int get currentIndex => _currentIndex;
  bool get isImmersive => _isImmersive;

  void setIndex(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      _isImmersive = false; // Reset immersive mode when switching screens
      notifyListeners();
    }
  }

  void setImmersive(bool value) {
    if (_isImmersive != value) {
      _isImmersive = value;
      notifyListeners();
    }
  }
}
