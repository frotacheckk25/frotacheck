import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/config/app_links.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_build_info.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/web_download.dart';

class DistribuicaoAppPage extends StatefulWidget {
  const DistribuicaoAppPage({super.key});

  @override
  State<DistribuicaoAppPage> createState() => _DistribuicaoAppPageState();
}

class _DistribuicaoAppPageState extends State<DistribuicaoAppPage> {
  final _supabase = Supabase.instance.client;
  final _qrKey = GlobalKey();

  bool _loading = true;
  bool? _online;
  AppBuildInfo? _buildInfo;

  bool _isMaster = false;
  String? _minhaEmpresaNome;

  List<Map<String, dynamic>> _empresas = [];
  String? _selectedEmpresaId;
  String? _selectedEmpresaNome;

  int? _empresasAtivas;
  int? _totalUsuarios;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final auth = context.read<AppAuthProvider>();
    _isMaster = auth.isMaster;
    _minhaEmpresaNome = auth.empresaNome;

    try {
      final futures = <Future>[];

      // Status online: uma consulta leve e rápida — se falhar/expirar,
      // consideramos offline.
      futures.add(
        _supabase
            .from('empresas')
            .select('id')
            .limit(1)
            .timeout(const Duration(seconds: 5))
            .then((_) => _online = true)
            .catchError((_) => _online = false),
      );

      futures.add(loadAppBuildInfo().then((v) => _buildInfo = v));

      if (_isMaster) {
        futures.add(
          _supabase.from('empresas').select('id, nome, status').order('nome').then((res) {
            final list = List<Map<String, dynamic>>.from(res as List);
            _empresas = list;
            _empresasAtivas = list.where((e) => (e['status'] ?? '') == 'ativo').length;
            if (_selectedEmpresaId == null && list.isNotEmpty) {
              _selectedEmpresaId = list.first['id']?.toString();
              _selectedEmpresaNome = list.first['nome']?.toString();
            }
          }),
        );
        futures.add(
          _supabase
              .from('user_profiles')
              .select('id')
              .count(CountOption.exact)
              .then((res) => _totalUsuarios = res.count),
        );
      }

      await Future.wait(futures);
    } catch (e) {
      _online ??= false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _empresaAtual =>
      _isMaster ? (_selectedEmpresaNome ?? '—') : (_minhaEmpresaNome ?? 'sua empresa');

  Future<void> _copiarLink() async {
    await Clipboard.setData(const ClipboardData(text: kFrotaCheckPwaUrl));
    if (mounted) showSuccess(context, 'Link copiado!');
  }

  Future<void> _compartilhar() async {
    final mensagem = frotaCheckShareMessage(_empresaAtual);
    try {
      // downloadFallbackEnabled/mailToFallbackEnabled desligados de propósito:
      // no Web, boa parte dos navegadores desktop não suporta o Web Share
      // API nativo, e o fallback de e-mail do share_plus só funciona se o SO
      // tiver um cliente de e-mail configurado — quando falha, cai no catch
      // abaixo e usamos nosso próprio fallback (copiar mensagem), que nunca
      // falha, em vez de abrir um rascunho de e-mail vazio inesperado.
      await SharePlus.instance.share(
        ShareParams(
          text: mensagem,
          subject: 'FrotaCheck',
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      try {
        await Clipboard.setData(ClipboardData(text: mensagem));
        if (mounted) showSuccess(context, 'Mensagem copiada! Cole no WhatsApp ou E-mail.');
      } catch (e) {
        if (mounted) showError(context, friendlyError(e));
      }
    }
  }

  Future<void> _baixarQrCode() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      if (kIsWeb) {
        // No Web, baixar direto via <a download> é muito mais confiável do
        // que o Web Share API (que boa parte dos navegadores desktop não
        // suporta para arquivos).
        downloadBytes(bytes, 'frotacheck-qrcode.png', 'image/png');
        if (mounted) showSuccess(context, 'QR Code baixado!');
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: 'frotacheck-qrcode.png', mimeType: 'image/png')],
          subject: 'QR Code FrotaCheck',
        ),
      );
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final permitido = auth.can(AppPermission.viewAppDistribution);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Distribuição do App'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar, tooltip: 'Atualizar'),
        ],
      ),
      body: !permitido
          ? const Center(
              child: Text(
                'Você não tem acesso a esta área.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _header(),
                      const SizedBox(height: 16),
                      _statsRow(),
                      const SizedBox(height: 16),
                      if (_isMaster) ...[
                        _empresaSelector(),
                        const SizedBox(height: 16),
                      ],
                      _qrEShareCard(),
                      const SizedBox(height: 16),
                      _mensagemProntaCard(),
                      const SizedBox(height: 16),
                      _compatibilidadeCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  // ── Seções ───────────────────────────────────────────────────────────────

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Distribuição do App',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Compartilhe o FrotaCheck com sua equipe — sem Google Play ou App Store.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final versao = _buildInfo == null
        ? '—'
        : 'v${_buildInfo!.version} (${_buildInfo!.buildNumber})';
    final publicado = _buildInfo?.publishedAt == null
        ? '—'
        : _fmtData(_buildInfo!.publishedAt!);

    final cards = <Widget>[
      _statCard('Versão', versao, Icons.tag_rounded, AppColors.secondary),
      _statCard('Última publicação', publicado, Icons.event_available_rounded, AppColors.info),
      _statCard(
        'Sistema',
        _online == null ? 'Verificando...' : (_online! ? 'Online' : 'Offline'),
        _online == true ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
        _online == true ? AppColors.success : AppColors.danger,
      ),
      if (_isMaster) ...[
        _statCard('Empresas ativas', '${_empresasAtivas ?? '—'}', Icons.apartment_rounded, AppColors.warning),
        _statCard('Usuários', '${_totalUsuarios ?? '—'}', Icons.groups_rounded, AppColors.primary),
      ],
    ];

    return Wrap(spacing: 10, runSpacing: 10, children: cards);
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(label.toUpperCase(),
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 10.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _empresaSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, color: AppColors.secondary, size: 18),
          const SizedBox(width: 10),
          const Text('Empresa:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedEmpresaId,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: _empresas
                  .map((e) => DropdownMenuItem(
                        value: e['id']?.toString(),
                        child: Text(e['nome']?.toString() ?? '—', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                final emp = _empresas.firstWhere((e) => e['id']?.toString() == v, orElse: () => {});
                setState(() {
                  _selectedEmpresaId = v;
                  _selectedEmpresaNome = emp['nome']?.toString();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrEShareCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            'Link de acesso — $_empresaAtual',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: kFrotaCheckPwaUrl,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            kFrotaCheckPwaUrl,
            style: const TextStyle(color: AppColors.secondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _copiarLink,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copiar Link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _compartilhar,
                icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                label: const Text('Compartilhar', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
              OutlinedButton.icon(
                onPressed: _baixarQrCode,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Baixar QR Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mensagemProntaCard() {
    final mensagem = frotaCheckShareMessage(_empresaAtual);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.chat_bubble_outline_rounded, color: AppColors.warning, size: 18),
              SizedBox(width: 8),
              Text('Mensagem pronta para compartilhar',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(mensagem, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: mensagem));
                if (mounted) showSuccess(context, 'Mensagem copiada!');
              },
              icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.secondary),
              label: const Text('Copiar mensagem', style: TextStyle(color: AppColors.secondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compatibilidadeCard() {
    final itens = const [
      ('Android', Icons.android_rounded),
      ('iPhone', Icons.phone_iphone_rounded),
      ('Windows', Icons.desktop_windows_rounded),
      ('Mac', Icons.laptop_mac_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compatível com',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: itens
                .map((item) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.$2, color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 6),
                          Text(item.$1, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  String _fmtData(DateTime d) {
    final local = d.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
