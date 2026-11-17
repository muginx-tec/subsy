#!/usr/bin/env python3
"""ceviri/anahtarlar.json (Türkçe kaynak yazılar) ve ceviri/<dil>.json (aynı sırada çeviriler) dosyalarından
ios/App/Localizable.xcstrings üretir. Yeni yazı eklenince: anahtarlar.json'a ve her dil dosyasına aynı sıraya ekle,
sonra bunu çalıştır. Eksik ya da fazla satırı olan dil dosyası hata verir, sessizce atlanmaz."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
keys = json.load(open(os.path.join(HERE, "anahtarlar.json"), encoding="utf-8"))
keys = [k.replace('\\"', '"') for k in keys]          # Swift kaynağındaki kaçışlı tırnak → gerçek tırnak
langs = {}
for f in sorted(os.listdir(HERE)):
    if f.endswith(".json") and f != "anahtarlar.json":
        rows = json.load(open(os.path.join(HERE, f), encoding="utf-8"))
        if len(rows) != len(keys):
            sys.exit(f"{f}: {len(rows)} satır var, {len(keys)} olmalı")
        langs[f[:-5]] = rows
strings = {}
for i, k in enumerate(keys):
    loc = {code: {"stringUnit": {"state": "translated", "value": rows[i]}} for code, rows in langs.items()}
    strings[k] = {"localizations": loc} if loc else {}
out = {"sourceLanguage": "tr", "strings": strings, "version": "1.0"}
path = os.path.join(HERE, "..", "ios", "App", "Localizable.xcstrings")
json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)
print(f"{len(keys)} yazı · diller: {', '.join(langs) or 'yok'} → ios/App/Localizable.xcstrings")
