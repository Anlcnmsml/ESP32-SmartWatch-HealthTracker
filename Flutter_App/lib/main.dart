import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

// --- SABİTLER ---
const String serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"; 
const String characteristicUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Security',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: const GuvenlikSistemiPage(),
    );
  }
}

class GuvenlikSistemiPage extends StatefulWidget {
  const GuvenlikSistemiPage({super.key});

  @override
  State<GuvenlikSistemiPage> createState() => _GuvenlikSistemiPageState();
}

class _GuvenlikSistemiPageState extends State<GuvenlikSistemiPage> {
  // --- FIREBASE REFERANSI ---
  final DatabaseReference _database = FirebaseDatabase.instance.refFromURL(
      "https://akilli-guvenlik-default-rtdb.europe-west1.firebasedatabase.app/");

  // --- BLE DEĞİŞKENLERİ ---
  BluetoothDevice? _bagliCihaz;

  // Abonelikler
  StreamSubscription? _taramaAboneligi;
  StreamSubscription? _baglantiDurumuAboneligi;
  StreamSubscription? _veriAboneligi;

  // --- Bluetooth Durum Takibi ---
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  bool _locationEnabled = false;

  bool _taramaYapiliyor = false;
  bool _baglaniyor = false;

  // --- DİL YÖNETİMİ ---
  String secilenDil = 'tr';

  final Map<String, Map<String, String>> dilPaketi = {
    'tr': {
      'app_title': 'Akıllı Güvenlik',
      'system_active': 'AKTİF',
      'system_passive': 'KAPALI',
      'status_safe': 'Sistem Durumu: GÜVENDE',
      'status_fall': '⚠️ DÜŞME ALGILANDI!',
      'settings_title': 'Eşik Değerleri',
      'save': 'Kaydet',
      'instant_pulse': 'ANLIK NABIZ',
      'alert_pulse': 'RİSKLİ NABIZ!',
      'alert_fall': 'DÜŞME ALGILANDI!',
      'alert_inactivity': 'UZUN SÜRE HAREKETSİZLİK',
      'alert_sos': 'ACİL YARDIM ÇAĞRISI',
      'bt_title': 'Bluetooth Cihazları',
      'bt_scan': 'Tara',
      'bt_stop': 'Durdur',
      'bt_connect': 'Bağlan',
      'bt_disconnect': 'Kes',
      'bt_connected': '✅ Cihaza bağlanıldı:',
      'bt_disconnected': '❌ Bağlantı kesildi.',
      'cancel': 'İptal',
      // ALARM EKRANI
      'alarm_calling': 'Acil yardım aranıyor...',
      'alarm_help_active': 'YARDIM ÇAĞRILIYOR!',
      'alarm_cancel_btn': 'İYİYİM, İPTAL ET',
      'alarm_return_normal': 'Normale Dön',
      // LOG MESAJLARI (YENİ EKLENDİ)
      'log_sys_opened': 'Sistem AÇILDI',
      'log_sys_closed': 'Sistem KAPATILDI',
      'log_settings_updated': 'Ayarlar güncellendi',
      'log_connection_failed': 'Bağlantı Başarısız!',
      'log_countdown': 'Geri sayım',
      'log_emergency_active': '🚨 ACİL DURUM AKTİF!',
      'log_user_cancelled': '✅ Kullanıcı alarmı iptal etti.',
      'log_calling_112': '📞 112 ARANIYOR...',
    },
    'en': {
      'app_title': 'Smart Security',
      'system_active': 'ACTIVE',
      'system_passive': 'OFF',
      'status_safe': 'System Status: SAFE',
      'status_fall': '⚠️ FALL DETECTED!',
      'settings_title': 'Threshold Settings',
      'save': 'Save',
      'instant_pulse': 'INSTANT PULSE',
      'alert_pulse': 'RISKY PULSE!',
      'alert_fall': 'FALL DETECTED!',
      'alert_inactivity': 'LONG INACTIVITY',
      'alert_sos': 'EMERGENCY SOS CALL',
      'bt_title': 'Bluetooth Devices',
      'bt_scan': 'Scan',
      'bt_stop': 'Stop',
      'bt_connect': 'Connect',
      'bt_disconnect': 'Disconnect',
      'bt_connected': '✅ Connected to:',
      'bt_disconnected': '❌ Disconnected.',
      'cancel': 'Cancel',
      // ALARM SCREEN
      'alarm_calling': 'Calling emergency...',
      'alarm_help_active': 'CALLING FOR HELP!',
      'alarm_cancel_btn': 'I\'M FINE, CANCEL',
      'alarm_return_normal': 'Return to Normal',
      // LOG MESSAGES (NEW)
      'log_sys_opened': 'System OPENED',
      'log_sys_closed': 'System CLOSED',
      'log_settings_updated': 'Settings updated',
      'log_connection_failed': 'Connection Failed!',
      'log_countdown': 'Countdown',
      'log_emergency_active': '🚨 EMERGENCY ACTIVE!',
      'log_user_cancelled': '✅ User cancelled alarm.',
      'log_calling_112': '📞 CALLING 112...',
    }
  };

  String t(String key) {
    return dilPaketi[secilenDil]![key] ?? key;
  }

  // --- SİSTEM DEĞİŞKENLERİ ---
  bool sistemAktifMi = true;
  bool hareketsizlikTakibi = true;

  int anlikNabiz = 75;
  String sistemDurumuYazisi = "GUVENDE";

  int minNabiz = 40;
  int maxNabiz = 120;

  Timer? _nabizTamponTimer;
  bool _nabizTakipte = false;
  final int _anormalNabizSuresi = 4;

  bool acilDurumEkraniAcik = false;
  String acilDurumBasligi = "";
  String acilDurumTuru = "";
  Color ekranRengi = Colors.red;

  int geriSayimSayaci = 0;
  int baslangicSuresi = 10;
  Timer? _geriSayimTimer;

  List<String> olayGecmisi = [];

  @override
  void initState() {
    super.initState();
    _baslangicIslemleri();
    _izinleriKontrolEt();
    _firebaseDinleyiciyiBaslat();

    FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted) setState(() => _taramaYapiliyor = isScanning);
    });

    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) setState(() => _adapterState = state);
    });

    _locationServisiniKontrolEt();
  }

  @override
  void dispose() {
    _baglantiDurumuAboneligi?.cancel();
    _veriAboneligi?.cancel();
    _taramaAboneligi?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }

  // --- Helper Metodlar ---
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _locationServisiniKontrolEt() async {
    bool serviceEnabled = await Permission.location.serviceStatus.isEnabled;
    if (mounted) {
      setState(() => _locationEnabled = serviceEnabled);
      if (!serviceEnabled) {
        _showSnackBar('Lütfen Konum (GPS) servisini açın!');
      }
    }
  }

  Future<void> _izinleriKontrolEt() async {
    var statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!mounted) return;

    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted ||
        statuses[Permission.location] != PermissionStatus.granted) {
      _showSnackBar('Uygulamanın çalışması için Bluetooth ve Konum izinleri gereklidir!');
    }
  }

  void _firebaseDinleyiciyiBaslat() {
    _database.child('kol_bandi_1').onValue.listen((event) {
      final data = event.snapshot.value as Map?;

      if (data != null) {
        if (data['durum'] != null) {
          String gelenDurum = data['durum'].toString();

          if (gelenDurum == "HAREKETSIZ" && !hareketsizlikTakibi) {
            // Gece modu
          } else {
            if (mounted) {
              setState(() {
                sistemDurumuYazisi = gelenDurum;
              });
            }

            if (gelenDurum == "DUSME" && !acilDurumEkraniAcik) {
              sinyalIsle("DUSME");
            } else if (gelenDurum == "HAREKETSIZ" && !acilDurumEkraniAcik) {
              if (hareketsizlikTakibi) sinyalIsle("HAREKETSIZ");
            } else if (gelenDurum == "BUTON" && !acilDurumEkraniAcik) {
              sinyalIsle("BUTON");
            }
          }
        }

        if (data['nabiz'] != null) {
          int gelenNabiz = int.parse(data['nabiz'].toString());
          if (_bagliCihaz == null) {
            if (gelenNabiz != anlikNabiz) {
              sinyalIsle("NABIZ",
                  gelenNabiz: gelenNabiz, firebaseGuncelle: false);
            }
          }
        }
      }
    });
  }

  void _firebaseGuncelle(int nabiz) {
    _database.child('kol_bandi_1').update({
      'nabiz': nabiz,
      'son_guncelleme': DateTime.now().toIso8601String(),
    });
  }

  // --- BLE TARAMA VE BAĞLANTI İŞLEMLERİ ---

  void _bluetoothPenceresiniAc() {
    if (_adapterState != BluetoothAdapterState.on) {
      _showSnackBar('Önce Bluetooth\'u açmalısınız!');
      return;
    }
    
    _cihazTara();

    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: 500,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('bt_title'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      if (_taramaYapiliyor) const CircularProgressIndicator()
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _taramaYapiliyor
                            ? null
                            : () {
                                _cihazTara();
                                setModalState(() {});
                              },
                        child: Text(t('bt_scan')),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () async {
                          await FlutterBluePlus.stopScan();
                        },
                        child: Text(t('bt_stop')),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: StreamBuilder<List<ScanResult>>(
                        stream: FlutterBluePlus.scanResults,
                        initialData: const [],
                        builder: (c, snapshot) {
                          final sonuclar = snapshot.data!.toList();

                          if (sonuclar.isEmpty && !_taramaYapiliyor) {
                             return const Center(child: Text("Cihaz bulunamadı. Tekrar tarayın."));
                          }

                          return ListView.builder(
                            itemCount: sonuclar.length,
                            itemBuilder: (c, i) {
                              final result = sonuclar[i];
                              final device = result.device;
                              final isConnected = (_bagliCihaz != null &&
                                  _bagliCihaz!.remoteId == device.remoteId);

                              String gorunurIsim = device.platformName.isNotEmpty 
                                  ? device.platformName 
                                  : "Cihaz (${device.remoteId})";

                              return ListTile(
                                title: Text(gorunurIsim), 
                                subtitle: Text(device.remoteId.toString()), 
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: isConnected
                                          ? Colors.red
                                          : Colors.green,
                                      foregroundColor: Colors.white),
                                  onPressed: _baglaniyor
                                      ? null
                                      : () {
                                          if (isConnected) {
                                            _baglantiyiKes();
                                            Navigator.pop(context);
                                          } else {
                                            _cihazaBaglan(device);
                                            Navigator.pop(context);
                                          }
                                        },
                                  child: Text(isConnected
                                      ? t('bt_disconnect')
                                      : t('bt_connect')),
                                ),
                              );
                            },
                          );
                        }),
                  )
                ],
              ),
            );
          });
        });
  }

  // 1. TARA
  void _cihazTara() async {
    if (_adapterState != BluetoothAdapterState.on) {
      _showSnackBar('Bluetooth açık değil! Lütfen açın.');
      return;
    }

    if (Theme.of(context).platform == TargetPlatform.android) {
       if (!_locationEnabled) {
          _locationServisiniKontrolEt();
          if (!_locationEnabled) {
             _showSnackBar('Cihazları bulmak için KONUM (GPS) açık olmalıdır!');
             return;
          }
       }
    }

    try {
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          androidUsesFineLocation: true
      );
    } catch (e) {
      debugPrint("Tarama Hatası: $e");
      _showSnackBar('Tarama başlatılamadı: $e');
    }
  }

  // 2. BAĞLAN
  Future<void> _cihazaBaglan(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    setState(() => _baglaniyor = true);

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      
      if (!mounted) return;

      if (Theme.of(context).platform == TargetPlatform.android) {
        await device.requestMtu(223); 
      }

      setState(() {
        _bagliCihaz = device;
        _baglaniyor = false;
      });

      _logEkle("${t('bt_connected')} ${device.platformName}");

      _baglantiDurumuAboneligi = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _baglantiyiKes();
        }
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == characteristicUuid) {
              await characteristic.setNotifyValue(true);

              _veriAboneligi = characteristic.lastValueStream.listen((value) {
                _veriIsle(value);
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Bağlantı Hatası: $e");
      if (mounted) {
        setState(() => _baglaniyor = false);
        _showSnackBar("Bağlantı başarısız oldu. Cihazı resetleyip tekrar deneyin.");
      }
      _logEkle(t('log_connection_failed'));
    }
  }

  // 3. VERİYİ İŞLE
  void _veriIsle(List<int> rawData) {
    // 1. Veriyi Çöz (Decode)
    String gelenVeri = utf8.decode(rawData);
    debugPrint("BLE Gelen: $gelenVeri"); 

    // A. DÜŞME KONTROLÜ
    if (gelenVeri.contains("DUSME ONAYLANDI")) {
      setState(() => sistemDurumuYazisi = "DUSME");
      sinyalIsle("DUSME");
    }

    // B. BUTON (SOS) KONTROLÜ 
    if (gelenVeri.contains("ACIL YARDIM") || gelenVeri.contains("BUTON")) {
       setState(() => sistemDurumuYazisi = "BUTON");
       sinyalIsle("BUTON");
    }
    
    // C. HAREKETSİZLİK KONTROLÜ
    if (gelenVeri.contains("HAREKETSIZ")) {
       setState(() => sistemDurumuYazisi = "HAREKETSIZ");
       if (hareketsizlikTakibi) {
          sinyalIsle("HAREKETSIZ");
       }
    }

    // D. NABIZ KONTROLÜ
    if (gelenVeri.contains("NABIZ:")) {
      try {
        List<String> ilkBolum = gelenVeri.split("NABIZ:");
        
        if (ilkBolum.length > 1) {
          String nabizKismi = ilkBolum[1].split("|")[0];
          int? val = int.tryParse(nabizKismi.trim());
          
          if (val != null) {
            sinyalIsle("NABIZ", gelenNabiz: val);
          }
        }
      } catch (e) {
        debugPrint("Nabız hatası: $e");
      }
    }

    // E. SİSTEM DURUMU GÜNCELLEME
    if (gelenVeri.contains("MOD:")) {
       if (!acilDurumEkraniAcik) {
         setState(() {
           if (gelenVeri.contains("ANALIZ")) {
             sistemDurumuYazisi = "ANALIZ EDİLİYOR...";
           } else if (gelenVeri.contains("NORMAL")) {
             sistemDurumuYazisi = "GUVENDE";
           }
         });
       }
    }
  }

  void _baglantiyiKes() async {
    if (_bagliCihaz != null) {
      await _veriAboneligi?.cancel();
      await _baglantiDurumuAboneligi?.cancel();

      await _bagliCihaz!.disconnect();

      if (mounted) {
        setState(() {
          _bagliCihaz = null;
        });
      }
      _logEkle(t('bt_disconnected'));
    }
  }

  // --- DİĞER FONKSİYONLAR ---

  Future<void> _baslangicIslemleri() async {
    await _loglariYukle();
  }

  Future<void> _loglariYukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        olayGecmisi = prefs.getStringList('kayitli_loglar') ?? [];
      });
    }
  }

  Future<void> _loglariKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('kayitli_loglar', olayGecmisi);
  }

  Future<void> _loglariTemizle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kayitli_loglar');
    if (mounted) {
      setState(() {
        olayGecmisi.clear();
      });
    }
  }

  void _logEkle(String mesaj) {
    String zaman = DateFormat('HH:mm:ss').format(DateTime.now());
    if (mounted) {
      setState(() {
        olayGecmisi.insert(0, "[$zaman] $mesaj");
      });
    }
    _loglariKaydet();
  }

  void sinyalIsle(String sinyalTuru,
      {int? gelenNabiz, bool firebaseGuncelle = true}) {
    if (!sistemAktifMi) return;

    if (sinyalTuru == "NABIZ" && gelenNabiz != null) {
      setState(() => anlikNabiz = gelenNabiz);

      if (firebaseGuncelle) {
        _firebaseGuncelle(gelenNabiz);
      }

      bool riskliDurum = (anlikNabiz < minNabiz || anlikNabiz > maxNabiz);

      if (riskliDurum) {
        if (!_nabizTakipte && !acilDurumEkraniAcik) {
          _nabizTakipte = true;
          _logEkle("${t('alert_pulse')} ($anlikNabiz BPM)");

          _nabizTamponTimer = Timer(Duration(seconds: _anormalNabizSuresi), () {
            _alarmBaslat(t('alert_pulse'), "NABIZ",
                sure: 10, renk: Colors.redAccent);
            _nabizTakipte = false;
          });
        }
      } else {
        if (_nabizTakipte) {
          _nabizTamponTimer?.cancel();
          _nabizTakipte = false;
        }
      }
      return;
    }

    if (sinyalTuru == "DUSME") {
      _alarmBaslat(t('alert_fall'), "DUSME", sure: 10, renk: Colors.red);
    }

    if (sinyalTuru == "HAREKETSIZ") {
      if (hareketsizlikTakibi) {
        _alarmBaslat(t('alert_inactivity'), "HAREKETSIZ",
            sure: 15, renk: Colors.orange);
      }
    }

    if (sinyalTuru == "BUTON") {
      _alarmBaslat(t('alert_sos'), "BUTON",
          sure: 5, renk: Colors.red.shade900);
    }
  }

  void _alarmBaslat(String baslik, String tur,
      {required int sure, required Color renk}) async {
    if (acilDurumEkraniAcik) return;

    HapticFeedback.heavyImpact();

    setState(() {
      acilDurumEkraniAcik = true;
      acilDurumBasligi = baslik;
      acilDurumTuru = tur;
      ekranRengi = renk;
      geriSayimSayaci = sure;
      baslangicSuresi = sure;
    });

    if (sure > 0) {
      _logEkle("⚠️ $tur! ${t('log_countdown')}: $sure sn."); // GÜNCELLENDİ

      _geriSayimTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!mounted) {
           timer.cancel();
           return;
        }
        setState(() {
          if (geriSayimSayaci > 0) {
            geriSayimSayaci--;
          } else {
            _geriSayimTimer?.cancel();
            _gercekAramaYap();
          }
        });

        if (geriSayimSayaci > 0) {
          HapticFeedback.heavyImpact();
        }
      });
    } else {
      _logEkle(t('log_emergency_active')); // GÜNCELLENDİ
      _gercekAramaYap();
    }
  }

  void _alarmiIptalEt() {
    _geriSayimTimer?.cancel();
    _nabizTamponTimer?.cancel();
    _nabizTakipte = false;
    _database.child('kol_bandi_1').update({'durum': 'GUVENDE'});
    setState(() => acilDurumEkraniAcik = false);
    _logEkle(t('log_user_cancelled')); // GÜNCELLENDİ
  }

  Future<void> _gercekAramaYap() async {
    if (acilDurumEkraniAcik) {
      for (int i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logEkle(t('log_calling_112')); // GÜNCELLENDİ

      final Uri telefon = Uri(scheme: 'tel', path: '112');
      if (await canLaunchUrl(telefon)) {
        await launchUrl(telefon);
      }
    }
  }

  void _ayarlariAc() {
    TextEditingController minC =
        TextEditingController(text: minNabiz.toString());
    TextEditingController maxC =
        TextEditingController(text: maxNabiz.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('settings_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Sınır Değerleri:"),
            const SizedBox(height: 10),
            TextField(
                controller: minC,
                decoration: const InputDecoration(labelText: "Min"),
                keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            TextField(
                controller: maxC,
                decoration: const InputDecoration(labelText: "Max"),
                keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          ElevatedButton(
              onPressed: () {
                setState(() {
                  minNabiz = int.tryParse(minC.text) ?? 40;
                  maxNabiz = int.tryParse(maxC.text) ?? 120;
                });
                _logEkle("${t('log_settings_updated')}: $minNabiz - $maxNabiz"); // GÜNCELLENDİ
                Navigator.pop(ctx);
              },
              child: Text(t('save'))),
        ],
      ),
    );
  }

  // --- UI için Durum Göstergesi ---
  Widget _buildBluetoothStatus() {
    IconData icon;
    Color color;

    switch (_adapterState) {
      case BluetoothAdapterState.on:
        icon = Icons.bluetooth;
        color = Colors.black; 
        break;
      case BluetoothAdapterState.off:
        icon = Icons.bluetooth_disabled;
        color = Colors.redAccent;
        break;
      default:
        icon = Icons.bluetooth_searching; 
        color = Colors.grey;
    }

    if (!_locationEnabled && Theme.of(context).platform == TargetPlatform.android) {
        return Row(
          children: [
            const Icon(Icons.location_off, color: Colors.redAccent),
            const SizedBox(width: 8),
            Icon(icon, color: color),
          ],
        );
    }

    return Icon(icon, color: color);
  }

  @override
  Widget build(BuildContext context) {
    Color durumRenk = sistemDurumuYazisi == "GUVENDE"
        ? Colors.green.shade900
        : Colors.red.shade900;

    Color durumArkaplan = sistemDurumuYazisi == "DUSME" ||
            sistemDurumuYazisi == "BUTON"
        ? Colors.red.shade100
        : (sistemDurumuYazisi == "HAREKETSIZ"
            ? Colors.orange.shade100
            : Colors.green.shade100);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('app_title')),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _buildBluetoothStatus(),
          ),
          
          IconButton(
            icon: Icon(Icons.bluetooth_searching, 
                color: (_bagliCihaz != null) ? Colors.blueAccent : Colors.black),
            onPressed: _bluetoothPenceresiniAc,
          ),
          
          PopupMenuButton<String>(
            onSelected: (String result) => setState(() => secilenDil = result),
            icon: const Icon(Icons.language),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'tr', child: Text('🇹🇷 Türkçe')),
              const PopupMenuItem<String>(
                  value: 'en', child: Text('🇺🇸 English')),
            ],
          ),
          Switch(
            value: sistemAktifMi,
            onChanged: (val) {
              setState(() => sistemAktifMi = val);
              // GÜNCELLENDİ (LOG)
              _logEkle(val ? t('log_sys_opened') : t('log_sys_closed'));
            },
            activeThumbColor: Colors.green,
            thumbColor: const WidgetStatePropertyAll(Colors.white),
          ),
          IconButton(
            icon: Icon(
                hareketsizlikTakibi ? Icons.directions_run : Icons.bedtime),
            color: hareketsizlikTakibi ? Colors.black : Colors.indigo,
            tooltip: "Hareketsizlik Takibi (Gece/Gündüz)",
            onPressed: () =>
                setState(() => hareketsizlikTakibi = !hareketsizlikTakibi),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _loglariTemizle,
          ),
          IconButton(icon: const Icon(Icons.settings), onPressed: _ayarlariAc),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Card(
                margin: const EdgeInsets.all(20),
                elevation: 5,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                color: sistemAktifMi ? Colors.white : Colors.grey.shade200,
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 15),
                        decoration: BoxDecoration(
                            color: durumArkaplan,
                            borderRadius: BorderRadius.circular(15)),
                        child: Text(
                          sistemDurumuYazisi == "DUSME"
                              ? t('status_fall')
                              : (sistemDurumuYazisi == "BUTON"
                                  ? t('alert_sos')
                                  : (sistemDurumuYazisi == "HAREKETSIZ"
                                      ? t('alert_inactivity')
                                      : t('status_safe'))),
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: durumRenk),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite,
                              size: 40,
                              color: sistemAktifMi ? Colors.red : Colors.grey),
                          const SizedBox(width: 10),
                          Text(t('instant_pulse'),
                              style: const TextStyle(
                                  color: Colors.grey, letterSpacing: 1.5)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text("$anlikNabiz",
                          style: TextStyle(
                              fontSize: 70,
                              fontWeight: FontWeight.bold,
                              color: Colors.black.withValues(
                                  alpha: sistemAktifMi ? 0.87 : 0.3))),
                      const Text("BPM",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                      const SizedBox(height: 10),
                      if (_bagliCihaz != null)
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(5)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bluetooth_connected,
                                  size: 16, color: Colors.blue),
                              const SizedBox(width: 5),
                              Text("Bağlı: ${_bagliCihaz!.platformName}",
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.blue)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(thickness: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: olayGecmisi.length,
                  itemBuilder: (context, index) {
                    return Card(
                      elevation: 0,
                      color: Colors.grey.shade50,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        leading: const Icon(Icons.history,
                            size: 16, color: Colors.grey),
                        title: Text(olayGecmisi[index],
                            style: const TextStyle(fontSize: 13)),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (acilDurumEkraniAcik)
            Container(
              color: ekranRengi,
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 80, color: Colors.white),
                  const SizedBox(height: 20),
                  Text(acilDurumBasligi,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  if (geriSayimSayaci > 0) ...[
                    Text(t('alarm_calling'), 
                        style: const TextStyle(color: Colors.white70, fontSize: 18)),
                    const SizedBox(height: 30),
                    Text("$geriSayimSayaci",
                        style: const TextStyle(
                            fontSize: 60,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        onPressed: _alarmiIptalEt,
                        icon: const Icon(Icons.check_circle, size: 30),
                        label: Text(t('alarm_cancel_btn'), 
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ekranRengi,
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(t('alarm_help_active'), 
                        style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 30),
                    OutlinedButton(
                      onPressed: _alarmiIptalEt,
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white),
                          foregroundColor: Colors.white),
                      child: Text(t('alarm_return_normal')), 
                    )
                  ]
                ],
              ),
            ),
        ],
      ),
    );
  }
}