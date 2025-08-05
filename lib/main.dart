// lib/main.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: QRScannerScreen(),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  _QRScannerScreenState createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  String _scanResult = 'Aguardando leitura...';
  String _statusMessage = '';
  // Alterado para um controlador anulável, que será criado a cada leitura
  MobileScannerController? cameraController; 
  bool _isScanning = false;
  List<dynamic> _resultadosDb = [];
  String _apiUrl = 'http://10.0.2.2:3000/api/armazem';
  
  double _zoomSliderValue = 0.0; 

  Map<String, dynamic>? _selectedArticle;
  List<dynamic> _localizacoes = [];

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('apiUrl') ?? 'http://10.0.2.2:3000/api/armazem';
      _statusMessage = 'URL da API carregada: $_apiUrl';
    });
  }

  Future<void> _navigateToSettings() async {
    final newApiUrl = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen(currentApiUrl: _apiUrl)),
    );
    if (newApiUrl != null) {
      setState(() {
        _apiUrl = newApiUrl;
        _statusMessage = 'URL da API atualizada: $_apiUrl';
      });
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() {
        _statusMessage = 'Permissão da câmara negada.';
      });
    }
  }

  void _startScanning() async {
    // --- ALTERAÇÕES CHAVE AQUI ---
    // Dispose do controlador anterior antes de criar um novo
    await cameraController?.dispose(); 

    setState(() {
      _selectedArticle = null;
      _localizacoes = [];
    });

    await _requestCameraPermission();
    final isPermissionGranted = await Permission.camera.isGranted;

    if (isPermissionGranted) {
      // Cria um novo controlador a cada nova leitura
      cameraController = MobileScannerController(); 
      setState(() {
        _isScanning = true;
        _scanResult = 'Aponte a câmara para o QR Code...';
        _statusMessage = '';
        _resultadosDb = [];
      });
    } else {
      setState(() {
        _statusMessage = 'Permissão da câmara não concedida.';
      });
    }
    // --- FIM DAS ALTERAÇÕES ---
  }

  Future<void> _fetchWarehouseContent(String qrcode) async {
    // Dispose do controlador após uma leitura bem-sucedida para libertar a câmara
    await cameraController?.dispose(); 
    cameraController = null;

    setState(() {
      _isScanning = false;
      _scanResult = qrcode;
      _statusMessage = 'A consultar a base de dados...';
    });

    final fullApiUrl = Uri.parse('$_apiUrl?qrcode=$qrcode');

    try {
      final response = await http.get(fullApiUrl);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> resultados = data['conteudo'];
        
        setState(() {
          _statusMessage = 'Resultados encontrados: ${resultados.length}';
          _resultadosDb = resultados;
        });
      } else {
        setState(() {
          _statusMessage = 'Não foi possível obter o conteúdo. Código: ${response.statusCode}';
          _resultadosDb = [];
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erro de conexão: Verifique se a API está a correr.';
        _resultadosDb = [];
      });
    }
  }

  Future<void> _fetchArticleLocations(Map<String, dynamic> artigo) async {
    setState(() {
      _statusMessage = 'A consultar localizações para o artigo...';
    });

    final fullApiUrl = Uri.parse('$_apiUrl?artigo=${artigo['Artigo']}');

    try {
      final response = await http.get(fullApiUrl);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> localizacoes = data['conteudo'];

        setState(() {
          _selectedArticle = artigo;
          _localizacoes = localizacoes;
          _statusMessage = 'Localizações encontradas: ${localizacoes.length}';
        });
      } else {
        setState(() {
          _statusMessage = 'Não foi possível obter as localizações. Código: ${response.statusCode}';
          _localizacoes = [];
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erro de conexão: Verifique se a API está a correr.';
        _localizacoes = [];
      });
    }
  }

  void _resetToQrResults() {
    setState(() {
      _selectedArticle = null;
      _localizacoes = [];
    });
  }

  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget mainContent;
    
    if (_isScanning && cameraController != null) {
      mainContent = MobileScanner(
        controller: cameraController,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final barcode = barcodes.first;
            if (barcode.rawValue != null) {
              _fetchWarehouseContent(barcode.rawValue!);
            }
          }
        },
      );
    } else if (_selectedArticle != null) {
      mainContent = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Artigo: ${_selectedArticle!['Artigo'] ?? 'N/A'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'Descrição: ${_selectedArticle!['Descricao'] ?? 'N/A'}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  border: Border.all(color: Colors.blueAccent),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 5, child: Text('Localização', style: TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('Quantidade', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              ..._localizacoes.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: Text(item['Localizacao'] ?? 'N/A')),
                      Expanded(flex: 2, child: Text(item['StkActual']?.toString() ?? 'N/A')),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      );
    } else {
      if (_resultadosDb.isNotEmpty) {
        mainContent = SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    border: Border.all(color: Colors.blueAccent),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('Artigo', style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 5, child: Text('Descrição', style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('Qtd.', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                ..._resultadosDb.map((item) {
                  return GestureDetector(
                    onTap: () => _fetchArticleLocations(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text(item['Artigo'] ?? 'N/A')),
                          Expanded(flex: 5, child: Text(item['Descricao'] ?? 'N/A')),
                          Expanded(flex: 2, child: Text(item['StkActual']?.toString() ?? 'N/A')),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      } else {
        mainContent = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _scanResult,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedArticle != null ? 'Localizações do Artigo' : 'Localização de Armazém'),
        backgroundColor: Colors.blueAccent,
        leading: _selectedArticle != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _resetToQrResults,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: mainContent),
          if (_isScanning)
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Slider(
                value: _zoomSliderValue,
                min: 0.0,
                max: 1.0,
                onChanged: (value) {
                  setState(() {
                    _zoomSliderValue = value;
                  });
                  cameraController?.setZoomScale(value);
                },
              ),
            ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: _startScanning,
              child: const Text('Iniciar Leitura', style: TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }
}