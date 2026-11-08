# Dash dil tanımı

Sürüm 0.1

Dash, sistem seviyesinde bir programlama dilidir. Söz dizimi Ada'nın
yapısına, alışkanlıkları C'ninkine yakındır. Derleyicisi DCM (Dash Compiler
Machine) saf Ada ile yazılmıştır.

---

## 1. Kaynak dosyaları

Dash kaynak dosyalarının uzantısı `.dh` olur. Bir dosya bir veya daha çok
fonksiyon içerebilir; giriş noktası `main` adlı fonksiyondur ve
parametre alamaz.

```dash
fs main is
begin
    println ( "merhaba" )
end
```

## 2. Sözcükler ve işaretler

### 2.1 Ayrılmış sözcükler

Yalnızca sekiz tanedir:

| Sözcük | Anlamı |
|---|---|
| `fs` | bir fonksiyonun başlangıcı |
| `is` | başlığın sonu, gövdenin başlangıcı |
| `begin` | gövdenin başlangıcı |
| `end` | bloğun sonu |
| `let` | değişken bildirimi |
| `int` | 64 bitlik tam sayı tipi |
| `st` | koşullu blok (şart) |
| `ut` | döngü bloğu |

Sözcükler büyük/küçük harfe duyarlıdır: `st` bir sözcüktür, `St` bir
tanımlayıcıdır.

### 2.2 İşaretler

```
(   )   <   >   :   =   "       yapı işaretleri
+   -   *   /   %             aritmetik işleçleri
```

Dilde `;` yoktur: **satır sonu** ifade ayracıdır. Yorum satır sonuna kadar
sürer ve `--` ile yazılır (Ada'da olduğu gibi). Metin içinde bir tırnak iki
kez yazılır.

### 2.3 Değişmezler

* **Tam sayı:** `42`, `0xFF` (onaltılık), `0b1011` (ikili).
* **Metin:** `"merhaba"`.
* **Doğru / yanlış:** `true`, `false`.

### 2.4 Tanımlayıcılar

Harf, rakam ve `_` işaretlerinden oluşur; ilk işaret harf veya `_` olmalıdır.
Büyük/küçük harfe duyarlıdır.

## 3. Söz dizimi

```
program     := { fonksiyon }

fonksiyon   := "fs" ad [ "(" { parametre } ")" ] [ ":" "int" ] "is"
                { bildirim } "begin" { deyim } "end"

parametre   := ad [ ":" "int" ]

bildirim    := "let" ad [ ":" "int" ] "=" ifade

deyim       := bildirim
             | ad "=" ifade
             | "st" "(" ifade ")" "begin" { deyim } "end"
             | "ut" "(" ifade ")" "begin" { deyim } "end"
             | fonksiyon
             | çağrı

ifade       := karşılaştırma
karşılaştırma := toplam { ( "<" | ">" ) toplam }
toplam      := çarpım { ( "+" | "-" ) çarpım }
çarpım      := bir { ( "*" | "/" | "%" ) bir }
bir         := [ "-" ] ilk
ilk         := tam_sayi | metin | "true" | "false"
             | ad [ "(" { ifade } ")" ] | "(" ifade ")"
```

Öncelik yüksekten düşüğe: `* / %`, sonra `+ -`, sonra `< >`.

## 4. Anlam

### 4.1 Fonksiyonlar

```dash
fs topla ( a : int b : int ) : int is
    let s : int = 0
begin
    s = a + b
    ret ( s )
end
```

* Parametreler `int` tipindedir. Bir parametrenin tipi yazılmazsa `int`
  sayılır.
* Sonuç tipi `:` ve `int` ile yazılabilir. **Özyinelemeli** bir fonksiyon
  kendi sonuç tipini çıkaramayacağı için bu yazım gereklidir.
* `ret ( ... )` kullanılmazsa fonksiyon bir **procedure**'dır ve değer
  döndürmez.

Bir fonksiyonun içinde başka bir fonksiyon yazılabilir; iç fonksiyon
dışarıdaki değişkenleri görebilir.

### 4.2 Değişkenler

```dash
let sayaç : int = 0      -- tip açıkça yazılmış
let ad = "dash"          -- tip değerden çıkarılır
```

Bir kapsamda aynı ad iki kez bildirilemez (gölgeleme yoktur).

### 4.3 Koşul ve döngü

`st` koşulu `bool` ya da sıfırdan farklı bir `int` olabilir:

```dash
st ( x > 10 ) begin
    println ( "buyuk" )
end
```

`ut` koşul doğru olduğu sürece yineler:

```dash
ut ( i < 10 ) begin
    i = i + 1
end
```

`else` dalı yoktur; bunun yerine koşul ters yazılır ya da `not` kullanılır.

### 4.4 Tipler

`int` (64 bitlik işaretli), `bool` ve `string` (sınırsız metin) vardır.

| İşlem | İzin verilen tipler | Sonuç |
|---|---|---|
| `+ - * / %` | `int`, `int` | `int` |
| `+` | `string`, `string` | `string` (birleştirme) |
| `< >` | `int`,`int` veya `string`,`string` | `bool` |
| `=` | — | atama (karşılaştırma `eq` ile) |

`/` sıfıra bölmede çalışma hatası verir. `%` kalanı, `mod` gibi, negatif
sayılarda aşağı yuvarlar.

## 5. Gömülü fonksiyonlar

Bunlar ayrılmış sözcük değildir; sıradan tanımlayıcı adlarıdır.

| Çağrı | Anlamı | Sonuç |
|---|---|---|
| `print ( v )` | değeri yazar, satır sonu yazmaz | — |
| `println ( v )` | değeri yazar, satır sonu yazar | — |
| `text ( v )` | sayıyı/metni metne çevirir | `string` |
| `concat ( a b )` | iki metni birleştirir | `string` |
| `len ( s )` | metnin uzunluğu | `int` |
| `read ( )` | standart girdiden bir satır okur | `string` |
| `readint ( )` | standart girdiden bir sayı okur | `int` |
| `abs ( n )` | mutlak değer | `int` |
| `not ( b )` | mantıksal değil | `bool` |
| `and ( a b )` | mantıksal ve | `bool` |
| `or ( a b )` | mantıksal veya | `bool` |
| `eq ( a b )` | eşitlik | `bool` |
| `ne ( a b )` | eşit değil | `bool` |
| `min ( a b )` | küçük olan | `int` |
| `max ( a b )` | büyük olan | `int` |
| `ret ( v )` | fonksiyondan dön | — |

Çoklu argümanlı çağrılarda argümanlar boşlukla ayrılır (`add ( 1 2 )`);
virgül de kabul edilir.

## 6. DCM

```
dcm build <file.dh> [-o <ad.exe>] [--keep-ada]
dcm run   <file.dh>
dcm check <file.dh>
dcm ast   <file.dh>
dcm version
```

### 6.1 Derleme yolu

1. Kaynak okunur, sözcüklere ayrılır.
2. Sözdizimi ağacı kurulur.
3. Anlamsal analiz yapılır: kapsamlar, tipler, gömülü fonksiyon denetimi.
4. Ağaç Ada kaynak koduna çevrilir (`dash_codegen`).
5. GNAT o kaynağı derler, sonuç bir `.exe` dosyasıdır.

Derleme sırasında üretilen Ada kodu geçici bir klasörde durur ve sonra
silinir; `--keep-ada` ile saklanabilir.

### 6.2 Sanal makine

`dcm run` aynı ağacı yorumlayıcıda çalıştırır. Araç zincirine gerek
duymaz, bu yüzden hızlı geliştirme içindir. Sanal makinenin anlamı, native
back end'in anlamıyla aynıdır; test paketi bu ikisini karşılaştırır.

### 6.3 Hata iletileri

```
ornek.dh: line 7: 'x' is not declared
ornek.dh: line 3, column 5: expected '=' in the declaration of 'sayi'
```

## 7. Örnekler

### 7.1 Fibonacci

```dash
fs fib ( n : int ) : int is
    let a : int = 0
    let b : int = 1
    let i : int = 0
    let r : int = 0
begin
    ut ( i < n ) begin
        r = a + b
        a = b
        b = r
        i = i + 1
    end
    ret ( a )
end

fs main is
    let i : int = 0
begin
    ut ( i < 10 ) begin
        println ( fib ( i ) )
        i = i + 1
    end
end
```

### 7.2 Metinler

```dash
fs main is
    let a = "Dash"
    let b = " dili"
    let c = a + b
begin
    println ( c )
    println ( len ( c ) )
    println ( concat ( "Merhaba" " dunya" ) )
end
```
