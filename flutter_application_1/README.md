# flutter_application_1

A new Flutter project.

## Test ortamı

Yeni kayıt sonrasında kullanıcı isteğe bağlı olarak banka/hesap adını,
başlangıç bakiyesini ve bu bakiyenin tarihini girebilir. Başlangıç bakiyesi
gelir olarak kaydedilmez; dashboard bakiyesini hesaplarken bu tutarı baz alır
ve aynı bankadaki daha sonraki işlemleri ekler. PDF yükleme ekranında aynı banka
ve tarih seçilerek ekstre ilişkilendirilebilir; bu bilgiler PDF geçmişinde
gösterilir. Kurulum sırasında kategori bazlı aylık limitler ve birikim hedefi
de eklenebilir.
Uygulama bu ayki giderleri limitlerle karşılaştırır ve limitin %80'inde ve
aşımında bildirim verir. Birikim hedefindeki ilerleme Planlar ekranından
eklenen birikim kayıtlarıyla takip edilir.

Flutter testleri için Flutter `3.44.2` ve Dart `3.12.2` kullanılır:

```powershell
flutter pub get
flutter test
```

Backend testleri proje içindeki Python sanal ortamında çalışır. Windows PowerShell:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r backend\requirements.txt
Set-Location backend
python -m pytest -q
Set-Location ..
```

Backend ortam değişkenleri için `backend/.env.example` dosyasını `backend/.env` olarak kopyalayın. `.env` dosyası gizli değerler içerdiği için Git'e eklenmemelidir.

GitHub'a push veya pull request açıldığında `.github/workflows/tests.yml`, Flutter ve backend testlerini otomatik çalıştırır.

## API test ortamını açma

Backend'i çalıştırın:

```powershell
cd backend
..\.venv\Scripts\python.exe -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

Swagger arayüzü: `http://127.0.0.1:8000/docs`

### Postman

Postman'da `postman/FinancialCoach.local.postman_environment.json` environment dosyasını ve `postman/FinancialCoach.postman_collection.json` collection dosyasını import edin. Önce `Health`, sonra collection içindeki istekleri sırayla çalıştırın. Register isteği her çalıştırmada yeni bir test kullanıcısı üretir.

### Playwright API testi

Backend açıkken ayrı bir terminalde:

```powershell
cd e2e
npm install
npx playwright test
```

Başka bir API adresi kullanıyorsanız:

```powershell
$env:API_BASE_URL = "http://127.0.0.1:8001"
npx playwright test
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
