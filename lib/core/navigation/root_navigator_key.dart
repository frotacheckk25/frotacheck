import 'package:flutter/material.dart';

/// Navigator global usado para abrir telas a partir de código fora da árvore
/// de widgets — ex.: toque numa notificação push, com o app em segundo
/// plano ou recém-aberto a partir dela (sem BuildContext local disponível).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
