# Pemprosesan Data dan Pematuhan Privasi

[English](DATA_PROCESSING_AND_PRIVACY.md) · [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Español](DATA_PROCESSING_AND_PRIVACY.es.md) · [Português (Brasil)](DATA_PROCESSING_AND_PRIVACY.pt-BR.md)<br>
[Français](DATA_PROCESSING_AND_PRIVACY.fr.md) · [Deutsch](DATA_PROCESSING_AND_PRIVACY.de.md) · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md) · **Bahasa Melayu**

[Kembali ke laman utama](../readme/README.ms.md)

Skop: SDK HelloFace. Dokumen ini ditujukan kepada pihak yang mengintegrasikan SDK dan menerangkan aliran data semasa serta tanggungjawab mereka dalam pengurusan data. Dokumen ini tidak menggantikan dasar privasi aplikasi atau perkhidmatan pihak yang mengintegrasikan SDK dan tidak bermakna mana-mana pelaksanaan telah disahkan mematuhi peraturan.

## Tempat pemprosesan berlaku

SDK melakukan pengesanan wajah, penangkapan wajah, pengekstrakan ciri, pengesanan liveness, perbandingan dan carian pada peranti. SDK itu sendiri tidak mengumpul atau menghantar sebarang data.
Lapisan SDK tidak mengisytiharkan kebenaran atau keupayaan rangkaian. Aplikasi hos mesti menerangkan tujuan kebenaran kamera, pemilihan foto dan kebenaran rangkaian yang digunakannya.

## Data yang terlibat

| Data | Tujuan dan batas penggunaan |
|---|---|
| Bingkai kamera, foto yang dipilih atau diimport, dan potongan imej wajah | Pengesanan, penangkapan, pengesanan liveness, pengekstrakan ciri dan pratonton; penyimpanan tambahan imej asal bergantung pada aplikasi |
| Ciri wajah, ID rekod, kumpulan dan tag | Pendaftaran, carian dan perbandingan dalam galeri setempat; rekod boleh disimpan secara berterusan pada peranti selepas pendaftaran atau import |
| Keadaan masa jalan SDK setempat, tetapan aplikasi dan log | Operasi dan diagnostik; diurus secara berasingan daripada galeri wajah untuk kegunaan aplikasi, dengan prinsip meminimumkan data turut diterapkan pada log |
| Versi sistem pengendalian dan model perkakasan | Membolehkan SDK memilih strategi pelaksanaan yang dioptimumkan untuk sistem pengendalian dan konfigurasi perkakasan yang berbeza |

## Tanggungjawab pihak yang mengintegrasikan SDK

Pihak yang mengintegrasikan SDK bertanggungjawab mengendalikan dan mengurus data wajah secara sah serta mematuhi keperluan yang terpakai bagi aplikasi atau perkhidmatan yang menggunakan SDK, berdasarkan kes penggunaan, aktiviti pemprosesan dan peraturan di setiap negara atau wilayah pelaksanaan. Ini termasuk pengumpulan, penggunaan, penyimpanan, akses, perkongsian, pemindahan dan pemadaman. Mereka juga mesti memberikan maklumat yang jelas kepada pengguna tentang pemprosesan data, menyediakan saluran untuk permintaan berkaitan dan mengendalikan permintaan tersebut.

Seni bina SDK semasa yang beroperasi secara luar talian pada peranti memastikan pengiraan data wajah kekal pada peranti untuk membantu melindungi data pengguna sejak peringkat reka bentuk dan mengurangkan risiko pendedahan kepada perkhidmatan luar. Pihak yang mengintegrasikan SDK bertanggungjawab terhadap kawalan akses, perlindungan penyimpanan, mekanisme pengekalan dan pemadaman, serta notis, kebenaran dan langkah keselamatan yang terpakai bagi sebarang penyimpanan data, penyegerakan awan atau pemprosesan lain yang dilaksanakan oleh aplikasi atau perkhidmatan mereka.

SDK semasa tidak menyokong pengecaman wajah bagi kanak-kanak di bawah umur 12 tahun dan tidak boleh digunakan dalam senario kewangan.

Untuk bantuan integrasi SDK atau melaporkan isu keselamatan SDK, pihak yang mengintegrasikan SDK boleh menghubungi [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com).
