# Dash

**Dash** küçük, sistem seviyesinde (low level) bir programlama dilidir.
Söz dizimi Ada'ya, C'nin okunabilirliğine benzer; derleyicisi **DCM**
(Dash Compiler Machine) **saf Ada** ile yazılmıştır. Hiçbir yerde C
kullanılmaz.

Dash **derlenen** bir dildir: `dcm build` bir `.dh` dosyasını alır, Ada
kaynak koduna çevirir ve gerçek bir **native `.exe`** üretir.

```
fs main is
    let i : int = 0
begin
    ut ( i < 5 ) begin
        println ( "sayi" )
        println ( i )
        i = i + 1
    end
end
```

```
$ dcm build examples\fib.dh -o fib.exe
dcm: built fib.exe
$ fib.exe
0
1
1
2
3
```

---

## 1. Kurulum

Dash'in derleyicisi GNAT ister. MSYS2 ile:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-gcc-ada mingw-w64-ucrt-x86_64-gprbuild
```

Alternatif olarak Alire kullanılabilir (Alire kendi GNAT toolchain'ini
kurabilir):

```sh
alr toolchain --install
```

DCM, GNAT'i şu yerlerde arar: `DASH_GNAT` ortam değişkeni, `PATH` üzerindeki
`gnatmake`, `C:\msys64\ucrt64\bin\gnatmake.exe`,
`C:\msys64\mingw64\bin\gnatmake.exe`.

## 2. DCM'nin derlenmesi

```sh
gprbuild -P dash.gpr        # bin\dcm_main.exe üretir
```

Alire ile:

```sh
alr build
alr run -- dcm_main version
```

## 3. Kullanım

| Komut | Ne yapar |
|---|---|
| `dcm build <file.dh> [-o <ad.exe>] [--keep-ada]` | programı native bir çalıştırılabilir dosyaya derler |
| `dcm run <file.dh>` | programı DCM'nin sanal makinesinde çalıştırır (hızlı geliştirme için) |
| `dcm check <file.dh>` | yalnızca analiz eder, hataları bildirir |
| `dcm ast <file.dh>` | sözdizimi ağacını basar |
| `dcm version` | sürümü yazar |

`--keep-ada` verilirse üretilen Ada kaynağı `ad.exe.dcm` klasöründe
saklanır — DCM'in çevirinin kendisi okunmak isteniyorsa işe yarar.

## 4. Dilin özeti

**Ayrılmış sözcükler** (sadece sekiz tane):

```
fs    is    begin    end    let    int    st    ut
```

**İşaretler:** `(  )  <  >  :  =  "` ve aritmetik için `+  -  *  /  %`.

* Satır sonu ifade ayracıdır; dilde `;` yoktur.
* `--` satır sonuna kadar yorum yapar (Ada tarzı).
* Metinler çift tırnaklıdır; içindeki tırnak iki kez yazılır: `"say ""hi"""`.
* Sayılar ondalık, `0x` onaltılık ve `0b` ikili yazılabilir.

**Temel kalıplar:**

```
fs <ad> ( <parametreler> ) [ : int ] is
    <let bildirimleri>
begin
    <deyimler>
end
```

* `st ( <koşul> ) begin ... end` — koşul doğruysa çalıştırır.
* `ut ( <koşul> ) begin ... end` — koşul doğru olduğu sürece çalıştırır.
* `let <ad> [ : int ] = <değer>` — değişken bildirimi.
* `<ad> = <değer>` — atama.
* `ret ( <değer> )` — fonksiyondan dön.
* `ret` kullanılmayan fonksiyon bir **procedure**'dır.

**Gömülü fonksiyonlar** (adları sıradan tanımlayıcılardır, ayrılmış sözcük
değildir):

`print` `println` `text` `concat` `len` `read` `readint` `abs` `not` `and`
`or` `eq` `ne` `min` `max` `ret`

`=` atama için ayrıldığından eşitlik `eq`, eşit değil `ne` ile yapılır.

Tam dil tanımı: [docs/LANGUAGE.md](docs/LANGUAGE.md).

## 5. Proje yapısı

```
dash/
  alire.toml            Alire paketi
  dash.gpr              GNAT proje dosyası
  src/
    dash_lex.*          sözcük çözümleyici
    dash_ast.*          sözdizimi ağacı
    dash_parse.*        özyinelemeli iniş ayrıştırıcı
    dash_sema.*         sembol tablosu ve tip denetimi
    dash_vm.*           sanal makine (hızlı çalıştırma)
    dash_codegen.*      native back end: Dash -> Ada
    dash_builtin.*      gömülü fonksiyonların tanımı
    dcm_main.adb        komut satırı arayüzü
  examples/             örnek programlar (.dh)
  tests/run_tests.ps1   test paketi
  docs/LANGUAGE.md      dil tanımı
```

## 6. Testler

```sh
gprbuild -P dash.gpr
powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1
```

Test paketi her örneği iki kez çalıştırır: bir kez sanal makinede, bir kez
DCM'in ürettiği native çalıştırılabilir dosyada. İki çıktının aynı olması
gerekir. Ayrıca hata iletileri de sınanır.

Durum: **24 sınama, hepsi geçiyor.**

## 7. Durum

Çalışan:

* sözcük çözümleyici, ayrıştırıcı, anlamsal analiz (tipler, kapsamlar, gömülü
  fonksiyon denetimi),
* sanal makine,
* native back end: Dash -> Ada -> `.exe`,
* hata iletileri (satır ve sütun ile).

Yol haritası:

* `string` ve `bool` için tür adları (şu an yalnızca `int` yazılabiliyor,
  `let` tipi kendiliğinden çıkarıyor),
* diziler ve kayıtlar,
* `while` dışında `for` döngüsü,
* doğrudan x86-64 hedefi (Ada kaynağı üretmek yerine).
