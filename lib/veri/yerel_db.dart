import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Cihazdaki yerel veritabanı (SQLite). Uygulama ekranları yalnızca buradan okur; ağ yalnızca senkron motoru içindir.
/// Her kullanıcı için ayrı dosya açılır (`ozelkalem_YONETICINO.db`).
class YerelDb {
  YerelDb._(this.db, this.yol);

  final Database db;
  final String yol;

  static const int surum = 10;

  static Future<YerelDb> ac(String dosyaAdi, {DatabaseFactory? fabrika}) async {
    final f = fabrika ?? databaseFactory;
    final yol = dosyaAdi == inMemoryDatabasePath
        ? dosyaAdi
        : p.join(await f.getDatabasesPath(), dosyaAdi);
    final db = await f.openDatabase(
      yol,
      options: OpenDatabaseOptions(
        version: surum,
        onCreate: _olustur,
        onUpgrade: _yukselt,
      ),
    );
    return YerelDb._(db, yol);
  }

  static Future<void> sil(String dosyaAdi, {DatabaseFactory? fabrika}) async {
    final f = fabrika ?? databaseFactory;
    await f.deleteDatabase(p.join(await f.getDatabasesPath(), dosyaAdi));
  }

  Future<void> kapat() => db.close();

  /// v1 → v2: talep ayrıntı önbelleği ve adres listesi önbelleği. v2 → v3: programlar (takvim) tabloları.
  static Future<void> _yukselt(Database db, int eski, int yeni) async {
    if (eski < 2) await _ekTablolar(db);
    if (eski < 3) await _programTablolari(db);
    if (eski < 4) await _randevuTablolari(db);
    if (eski < 5) await _faaliyetTablolari(db);
    if (eski < 6) await _rehberTablolari(db);
    if (eski < 7) await _yazismaTablolari(db);
    if (eski < 9) await _tbmmTablolari(db);
    if (eski < 10) await _bolgeTablolari(db);
    if (eski == 7) {
      await db.execute(
        "ALTER TABLE yazismalar ADD COLUMN talep_adi TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  static Future<void> _programTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS programlar (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        adi TEXT NOT NULL DEFAULT '',
        tarih1 TEXT NOT NULL DEFAULT '',
        tarih2 TEXT NOT NULL DEFAULT '',
        yer TEXT NOT NULL DEFAULT '',
        notlar TEXT NOT NULL DEFAULT '',
        renk TEXT NOT NULL DEFAULT '#3788d8',
        randevu_no INTEGER NOT NULL DEFAULT 0,
        hat_json TEXT,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_programlar_tarih ON programlar (silindi, tarih1)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS p_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_p_kuyruk_kayit ON p_kuyruk (yerel_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS program_ek (no INTEGER PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _randevuTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS randevular (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        katno INTEGER NOT NULL DEFAULT 1,
        durum INTEGER NOT NULL DEFAULT 1,
        adi TEXT NOT NULL DEFAULT '',
        unvan TEXT NOT NULL DEFAULT '',
        telefon TEXT NOT NULL DEFAULT '',
        tarih TEXT NOT NULL DEFAULT '',
        sure_dk INTEGER NOT NULL DEFAULT 30,
        yer TEXT NOT NULL DEFAULT '',
        notlar TEXT NOT NULL DEFAULT '',
        ekleyen INTEGER NOT NULL DEFAULT 0,
        program_no INTEGER NOT NULL DEFAULT 0,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_randevular_tarih ON randevular (silindi, tarih)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS r_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_r_kuyruk_kayit ON r_kuyruk (yerel_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS randevu_ek (no INTEGER PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _faaliyetTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS faaliyetler (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        katno INTEGER NOT NULL DEFAULT 0,
        yer INTEGER NOT NULL DEFAULT 0,
        adi TEXT NOT NULL DEFAULT '',
        tarih TEXT NOT NULL DEFAULT '',
        icerik TEXT NOT NULL DEFAULT '',
        notlar TEXT NOT NULL DEFAULT '',
        haberler TEXT NOT NULL DEFAULT '',
        ekleyen INTEGER NOT NULL DEFAULT 0,
        resim INTEGER NOT NULL DEFAULT 0,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_faaliyetler_tarih ON faaliyetler (silindi, tarih)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS f_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_f_kuyruk_kayit ON f_kuyruk (yerel_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS faaliyet_ek (no INTEGER PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _rehberTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kisiler (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        katno INTEGER NOT NULL DEFAULT 0,
        adi TEXT NOT NULL DEFAULT '',
        unvan TEXT NOT NULL DEFAULT '',
        cep1 TEXT NOT NULL DEFAULT '',
        cep2 TEXT NOT NULL DEFAULT '',
        is1 TEXT NOT NULL DEFAULT '',
        isd1 TEXT NOT NULL DEFAULT '',
        is2 TEXT NOT NULL DEFAULT '',
        isd2 TEXT NOT NULL DEFAULT '',
        faks TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        adres TEXT NOT NULL DEFAULT '',
        notu TEXT NOT NULL DEFAULT '',
        dogum TEXT NOT NULL DEFAULT '',
        kara INTEGER NOT NULL DEFAULT 0,
        harf TEXT NOT NULL DEFAULT '#',
        sira TEXT NOT NULL DEFAULT '',
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_kisiler_sira ON kisiler (silindi, harf, sira)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS h_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_h_kuyruk_kayit ON h_kuyruk (yerel_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gorusmeler (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        adi TEXT NOT NULL DEFAULT '',
        unvan TEXT NOT NULL DEFAULT '',
        tel1 TEXT NOT NULL DEFAULT '',
        dah1 TEXT NOT NULL DEFAULT '',
        tel2 TEXT NOT NULL DEFAULT '',
        dah2 TEXT NOT NULL DEFAULT '',
        konu TEXT NOT NULL DEFAULT '',
        d1 INTEGER NOT NULL DEFAULT 0,
        d2 INTEGER NOT NULL DEFAULT 0,
        t1 TEXT NOT NULL DEFAULT '',
        t2 TEXT NOT NULL DEFAULT '',
        notum TEXT NOT NULL DEFAULT '',
        ekleyen INTEGER NOT NULL DEFAULT 0,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_gorusmeler_t1 ON gorusmeler (silindi, t1)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS g_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_g_kuyruk_kayit ON g_kuyruk (yerel_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS rehber_ek (anahtar TEXT PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _yazismaTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS yazismalar (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        talep_eden TEXT NOT NULL DEFAULT '',
        talep_adi TEXT NOT NULL DEFAULT '',
        kisi TEXT NOT NULL DEFAULT '',
        unvan TEXT NOT NULL DEFAULT '',
        icerik TEXT NOT NULL DEFAULT '',
        tarih TEXT NOT NULL DEFAULT '',
        logo INTEGER NOT NULL DEFAULT 1,
        imza INTEGER NOT NULL DEFAULT 1,
        imza_unvan INTEGER NOT NULL DEFAULT 1,
        imza_unvan_2 INTEGER NOT NULL DEFAULT 1,
        alt_yazi INTEGER NOT NULL DEFAULT 1,
        ekleyen INTEGER NOT NULL DEFAULT 0,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_yazismalar_tarih ON yazismalar (silindi, tarih DESC)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS y_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_y_kuyruk_kayit ON y_kuyruk (yerel_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS yazisma_ek (no INTEGER PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _tbmmTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbmm (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        tablo INTEGER NOT NULL DEFAULT 0,
        adi TEXT NOT NULL DEFAULT '',
        tarih TEXT NOT NULL DEFAULT '',
        icerik TEXT NOT NULL DEFAULT '',
        notlar TEXT NOT NULL DEFAULT '',
        ekleyen INTEGER NOT NULL DEFAULT 0,
        ek INTEGER NOT NULL DEFAULT 0,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_tbmm_tarih ON tbmm (silindi, tablo, tarih DESC)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tb_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_tb_kuyruk_kayit ON tb_kuyruk (yerel_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS tbmm_ek (no INTEGER PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _bolgeTablolari(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bolgeler (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        il INTEGER NOT NULL DEFAULT 0,
        ilce INTEGER NOT NULL DEFAULT 0,
        semt INTEGER NOT NULL DEFAULT 0,
        mahalle INTEGER NOT NULL DEFAULT 0,
        ilce_adi TEXT NOT NULL DEFAULT '',
        semt_adi TEXT NOT NULL DEFAULT '',
        mahalle_adi TEXT NOT NULL DEFAULT '',
        tarih TEXT NOT NULL DEFAULT '',
        ekleyen INTEGER NOT NULL DEFAULT 0,
        veri TEXT NOT NULL DEFAULT '{}',
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_bolgeler_liste ON bolgeler (silindi, ilce, no DESC)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bl_kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_bl_kuyruk_kayit ON bl_kuyruk (yerel_id)',
    );
  }

  static Future<void> _ekTablolar(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS talep_ek (no INTEGER PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS adres_onbellek (anahtar TEXT PRIMARY KEY, json TEXT NOT NULL, zaman INTEGER NOT NULL)',
    );
  }

  static Future<void> _olustur(Database db, int v) async {
    await _ekTablolar(db);
    await _programTablolari(db);
    await _randevuTablolari(db);
    await _faaliyetTablolari(db);
    await _rehberTablolari(db);
    await _yazismaTablolari(db);
    await _tbmmTablolari(db);
    await _bolgeTablolari(db);
    await db.execute('''
      CREATE TABLE talepler (
        yerel_id INTEGER PRIMARY KEY AUTOINCREMENT,
        no INTEGER UNIQUE,
        surum INTEGER NOT NULL DEFAULT 0,
        il INTEGER, ilce INTEGER, semt INTEGER, mahalle INTEGER,
        talep_eden TEXT NOT NULL DEFAULT '',
        tcno TEXT NOT NULL DEFAULT '',
        icerik TEXT NOT NULL DEFAULT '',
        telefon TEXT NOT NULL DEFAULT '',
        katno INTEGER NOT NULL DEFAULT 0,
        mulakat_tarihi TEXT,
        mulakat_yeri TEXT NOT NULL DEFAULT '',
        referans TEXT NOT NULL DEFAULT '',
        referans_telefon TEXT NOT NULL DEFAULT '',
        tarih TEXT,
        durum INTEGER NOT NULL DEFAULT 0,
        yapilan_islem TEXT NOT NULL DEFAULT '',
        sonuc TEXT NOT NULL DEFAULT '',
        ilgili_kurum TEXT NOT NULL DEFAULT '',
        hatirlatici INTEGER NOT NULL DEFAULT 0,
        hatirlatici_tarih TEXT,
        ekleyen INTEGER,
        ara TEXT NOT NULL DEFAULT '',
        bekleyen INTEGER NOT NULL DEFAULT 0,
        silindi INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
      'CREATE INDEX ix_talepler_tarih ON talepler (silindi, tarih DESC, no DESC)',
    );
    await db.execute('CREATE INDEX ix_talepler_ara ON talepler (ara)');
    await db.execute('''
      CREATE TABLE kuyruk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        istemci_id TEXT NOT NULL UNIQUE,
        tur TEXT NOT NULL,
        yerel_id INTEGER NOT NULL,
        no INTEGER,
        taban INTEGER,
        govde TEXT NOT NULL DEFAULT '{}',
        durum TEXT NOT NULL DEFAULT 'bekliyor',
        mesaj TEXT NOT NULL DEFAULT '',
        sunucu_json TEXT,
        onceki_json TEXT,
        olusturma INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX ix_kuyruk_kayit ON kuyruk (yerel_id)');
    await db.execute(
      'CREATE TABLE meta (anahtar TEXT PRIMARY KEY, deger TEXT)',
    );
    await db.execute(
      'CREATE TABLE ref_durum (no INTEGER PRIMARY KEY, adi TEXT NOT NULL, renk TEXT)',
    );
    await db.execute(
      'CREATE TABLE ref_kategori (no INTEGER PRIMARY KEY, adi TEXT NOT NULL)',
    );
  }
}
