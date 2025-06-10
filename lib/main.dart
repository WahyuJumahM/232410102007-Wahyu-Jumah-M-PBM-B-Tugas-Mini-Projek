import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Scanner App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: QRScannerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  @override
  _QRScannerScreenState createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final GlobalKey _globalKey = GlobalKey();
  QRViewController? controller;
  String? qrText;
  String? qrType;
  bool _isScanned = false;
  bool _isFlashOn = false;
  bool _storagePermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkAndRequestStoragePermission();
  }

  Future<void> _checkAndRequestStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 10+ (API 29+), we need to request MANAGE_EXTERNAL_STORAGE
      // For older versions, we use WRITE_EXTERNAL_STORAGE
      if (await Permission.storage.request().isGranted) {
        setState(() {
          _storagePermissionGranted = true;
        });
        return;
      }

      // If not granted, show rationale and request again
      if (await Permission.storage.shouldShowRequestRationale) {
        _showPermissionRationale();
      }

      // Final check if the user permanently denied the permission
      if (await Permission.storage.isPermanentlyDenied) {
        _showPermissionSettingsDialog();
      }
    } else {
      // For iOS, we don't need storage permission for this use case
      setState(() {
        _storagePermissionGranted = true;
      });
    }
  }

  void _showPermissionRationale() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Storage Permission Needed'),
        content: Text(
            'This app needs storage permission to save QR codes to your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Permission.storage.request();
              await _checkAndRequestStoragePermission();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permission Required'),
        content: Text(
            'Storage permission was permanently denied. Please enable it in app settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    if (controller != null) {
      controller!.pauseCamera();
      controller!.resumeCamera();
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (!_isScanned) {
        _isScanned = true;
        await controller.pauseCamera();

        final content = scanData.code;
        final type = _validateQRContent(content);

        setState(() {
          qrText = content;
          qrType = type;
        });

        _showResultDialog(content!, type);
      }
    });
  }

  String _validateQRContent(String? code) {
    if (code == null) return 'Unknown';
    final urlPattern = RegExp(r'^https?:\/\/');
    final emailPattern = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    final phonePattern = RegExp(r'^[\+]?[0-9]{10,15}$');
    final idPattern = RegExp(r'^\d+$');

    if (urlPattern.hasMatch(code)) {
      return 'URL';
    } else if (emailPattern.hasMatch(code)) {
      return 'Email';
    } else if (phonePattern.hasMatch(code)) {
      return 'Phone';
    } else if (idPattern.hasMatch(code)) {
      return 'ID';
    } else {
      return 'Text';
    }
  }

  void _showResultDialog(String content, String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.qr_code, color: Colors.blue),
            SizedBox(width: 8),
            Text('QR Code Detected'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Content:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    SelectableText(content),
                    SizedBox(height: 8),
                    Text(
                      'Type: $type',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Center(
                child: RepaintBoundary(
                  key: _globalKey,
                  child: Container(
                    color: Colors.white,
                    padding: EdgeInsets.all(16),
                    child: QrImageView(
                      data: content,
                      version: QrVersions.auto,
                      size: 150.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (type == 'URL')
            TextButton.icon(
              onPressed: () => _launchURL(content),
              icon: Icon(Icons.open_in_browser),
              label: Text('Open URL'),
            ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _saveQRToGallery(content);
              controller?.resumeCamera();
              setState(() => _isScanned = false);
            },
            icon: Icon(Icons.save),
            label: Text('Save QR'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              controller?.resumeCamera();
              setState(() => _isScanned = false);
            },
            icon: Icon(Icons.camera_alt),
            label: Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        _showSnackBar('Could not launch URL: $url');
      }
    } catch (e) {
      _showSnackBar('Error launching URL: $e');
    }
  }

  Future<void> _saveQRToGallery(String content) async {
    // Check permission again before saving
    await _checkAndRequestStoragePermission();
    
    if (!_storagePermissionGranted) {
      _showSnackBar('Storage permission is required to save QR codes');
      return;
    }

    try {
      RenderRepaintBoundary boundary = _globalKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Pictures');
        if (!await directory.exists()) {
          directory = (await getExternalStorageDirectory())!;
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String qrCodePath = '${directory.path}/QRCodes';
      Directory qrDirectory = Directory(qrCodePath);
      if (!await qrDirectory.exists()) {
        await qrDirectory.create(recursive: true);
      }

      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String fileName = 'qr_code_$timestamp.png';
      File file = File('$qrCodePath/$fileName');
      await file.writeAsBytes(pngBytes);

      File textFile = File('$qrCodePath/qr_result_$timestamp.txt');
      await textFile.writeAsString(
          'QR Content: $content\nType: $qrType\nScanned at: ${DateTime.now()}');

      if (Platform.isAndroid) {
        await _scanFile(file);
        await _scanFile(textFile);
      }

      _showSnackBar('QR Code saved to: ${file.path}');
    } catch (e) {
      _showSnackBar('Error saving QR Code: $e');
    }
  }

  Future<void> _scanFile(File file) async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('qr_scanner_channel');
        await platform.invokeMethod('scanFile', {'path': file.path});
      } on PlatformException catch (e) {
        debugPrint('Error scanning file: ${e.message}');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _toggleFlash() async {
    if (controller != null) {
      await controller!.toggleFlash();
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('QR Code Scanner'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _toggleFlash,
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            onPressed: () => _showSavedQRs(),
            icon: Icon(Icons.folder),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              margin: EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: QRView(
                  key: qrKey,
                  onQRViewCreated: _onQRViewCreated,
                  overlay: QrScannerOverlayShape(
                    borderColor: Colors.blue,
                    borderRadius: 10,
                    borderLength: 30,
                    borderWidth: 10,
                    cutOutSize: 250,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 32,
                          color: Colors.blue,
                        ),
                        SizedBox(height: 8),
                        Text(
                          qrText != null
                              ? 'Result: ${qrText!.length > 30 ? qrText!.substring(0, 30) + '...' : qrText!}'
                              : 'Point camera at QR Code',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                        if (qrType != null)
                          Text(
                            '(Type: $qrType)',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_isScanned) {
            controller?.resumeCamera();
            setState(() {
              _isScanned = false;
              qrText = null;
              qrType = null;
            });
          }
        },
        child: Icon(_isScanned ? Icons.refresh : Icons.qr_code_scanner),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _showSavedQRs() async {
    try {
      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Pictures');
        if (!await directory.exists()) {
          directory = (await getExternalStorageDirectory())!;
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String qrCodePath = '${directory.path}/QRCodes';
      Directory qrDirectory = Directory(qrCodePath);

      if (await qrDirectory.exists()) {
        List<FileSystemEntity> files = qrDirectory.listSync();
        List<File> qrFiles = files
            .whereType<File>()
            .where((file) => file.path.endsWith('.txt'))
            .toList();

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Saved QR Codes'),
            content: Container(
              width: double.maxFinite,
              height: 300,
              child: qrFiles.isEmpty
                  ? Center(child: Text('No saved QR codes yet'))
                  : ListView.builder(
                      itemCount: qrFiles.length,
                      itemBuilder: (context, index) {
                        File file = qrFiles[index];
                        String fileName = file.path.split('/').last;
                        return ListTile(
                          leading: Icon(Icons.qr_code),
                          title: Text(fileName),
                          subtitle: Text('Tap to view content'),
                          onTap: () async {
                            String content = await file.readAsString();
                            Navigator.of(context).pop();
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('QR Code Content'),
                                content: SelectableText(content),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
            ],
          ),
        );
      } else {
        _showSnackBar('No saved QR codes yet');
      }
    } catch (e) {
      _showSnackBar('Error opening folder: $e');
    }
  }
}