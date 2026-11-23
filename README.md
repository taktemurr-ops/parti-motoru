# parti-motoru

Parti ve Aile ailesinin ortak motoru. Bütün oyunlar aynı telefonda sırayla oynanır; ortak lobi oyuncu adlarını, takımları, süreyi, yaş paketini (çocuk / aile / herkes) ve oyuncuların kendi kelimelerini yönetir. 33 dil; her oyun için 100.000 tohumlanmış deste, her deste kurallara göre doğrulanır.

| Tür | Oyun |
|---|---|
| isim-sehir | İsim Şehir (33 dile göre harfler; Korece 초성, Çince pinyin baş harfi) |
| yasakli-kelime | Yasaklı Kelime (109 kart, TR/EN, 4 yasaklı sözcük) |
| ciz-tahmin | Çiz ve Tahmin Et (uygulama içi tuval, renkler, geri al) |
| sessiz-sinema | Sessiz Sinema |
| dogruluk-cesaret | Doğruluk mu Görev mi (aile dostu) |
| sise-cevirme | Çevir Bakalım (şişe yerine ok) |
| ben-kimim | Ben Kimim? (alında tutulur, görmeden dokunma alanları) |
| koylu-vampir | Köylü ve Vampir (uygulama anlatıcı) |
| casus-kim | Casus Kim? (30 mekân, 33 dil) |
| aile-bilgi | Aile Bilgi Yarışması (1-4 kişi, tek ekranda emoji soruları) |
| skor-tahtasi | Skor Tahtası (puan, zar, tur sayacı) |
| kelime-ipucu | Emoji İpucu (5×5 emoji, iki takım) |
| emoji-hikaye | Emoji Hikâye (özgün) |
| hafiza-zinciri | Hafıza Zinciri (özgün) |
| hizli-parmak | Hızlı Parmak (özgün) |

Veriler `lib/src/data/cards.dart` ve metinler `lib/src/texts.dart` dosyasında; ikisi de `proto/parti/mkdata.py` ve `proto/parti/mktexts.py` ile üretilir.
