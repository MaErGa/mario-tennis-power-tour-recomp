// partidas.h — importar y exportar partidas de emulador desde el menú de arranque.
//
// Lo implementa src/partidas.cpp; lo usa la pantalla «Partidas» del menú
// (parches/recomp-ui-0006-*.patch). Es C puro a propósito: el menú es C++ de otro proyecto y
// solo necesita estas funciones y estas estructuras.
//
// La partida del juego es un .sav de 32 KiB (SRAM) junto a la ROM, el mismo formato que usan
// mGBA, VisualBoyAdvance-M, RetroArch (.srm), BizHawk, no$gba y los flashcarts. Nada de aquí
// toca la partida si el archivo elegido no pasa las comprobaciones, y antes de sustituir la
// partida actual siempre se guarda una copia en «copias-de-partidas» (junto a config.ini).
#ifndef MTP_PARTIDAS_H
#define MTP_PARTIDAS_H

#ifdef __cplusplus
extern "C" {
#endif

// Códigos de resultado (MtpPartidaResultado.codigo).
enum {
    MTP_PARTIDA_OK = 0,
    MTP_PARTIDA_ERR_NO_EXISTE = 1,       // el archivo no existe o no se puede leer
    MTP_PARTIDA_ERR_VACIO = 2,           // el archivo mide 0 bytes
    MTP_PARTIDA_ERR_ESTADO_RAPIDO = 3,   // es un estado rápido (save state) de un emulador
    MTP_PARTIDA_ERR_OTRO_FORMATO = 4,    // mide de más y lo que sobra no es relleno (Flash, EEPROM, otro juego)
    MTP_PARTIDA_ERR_SIN_PARTIDA = 5,     // todavía no hay partida guardada del juego
    MTP_PARTIDA_ERR_ESCRIBIR = 6,        // no se pudo escribir el archivo
    MTP_PARTIDA_ERR_SIN_ROM = 7,         // no hay ROM elegida: no se sabe dónde está la partida
    MTP_PARTIDA_ERR_DEMASIADO_GRANDE = 8 // el archivo es enorme: no es una partida
};

typedef struct MtpPartidaResultado {
    int codigo;                          // MTP_PARTIDA_*
    unsigned long long bytes_origen;     // tamaño del archivo leído (0 si no se leyó)
    int recortado;                       // 1: traía relleno o una copia de más y se usaron 32 KiB
    int completado;                      // 1: medía menos de 32 KiB y se completó con 0xFF
    int vacia;                           // 1: la partida no contiene progreso (solo 0x00 o 0xFF)
    char copia[1024];                    // copia de seguridad que se hizo (UTF-8), o ""
} MtpPartidaResultado;

typedef struct MtpPartidaInfo {
    int existe;                          // 1 si hay un .sav junto a la ROM
    unsigned long long bytes;
    long long modificada;                // segundos Unix (hora de la última escritura)
    int vacia;                           // 1 si no contiene progreso
    char ruta[1024];                     // ruta del .sav (UTF-8), aunque todavía no exista
} MtpPartidaInfo;

typedef struct MtpCopia {
    char ruta[1024];                     // UTF-8
    unsigned long long bytes;
    long long modificada;                // segundos Unix
} MtpCopia;

// Estado de la partida del juego (la ROM es la que ha elegido el menú; "" o NULL = ninguna).
// Devuelve 0 si se pudo calcular la ruta, MTP_PARTIDA_ERR_SIN_ROM si no.
int mtp_partida_info(const char* rom, MtpPartidaInfo* out);

// Solo comprueba un archivo (no escribe nada): rellena codigo, bytes_origen, recortado,
// completado y vacia.
void mtp_partida_comprobar(const char* origen, MtpPartidaResultado* out);

// Pone `origen` como partida del juego. Guarda antes una copia de la actual (si la hay).
void mtp_partida_importar(const char* rom, const char* origen, MtpPartidaResultado* out);

// Escribe la partida del juego en `destino` (siempre 32 KiB). Si el nombre no lleva extensión,
// se le añade «.sav». No cambia la partida del juego.
void mtp_partida_exportar(const char* rom, const char* destino, MtpPartidaResultado* out);

// Guarda una copia de la partida actual en «copias-de-partidas».
void mtp_partida_copia(const char* rom, MtpPartidaResultado* out);

// Las copias de seguridad, de la más reciente a la más antigua (como mucho `max`).
// Devuelve cuántas hay.
int mtp_partida_copias(MtpCopia* out, int max);

// Pone una copia de seguridad como partida del juego (antes guarda la actual).
void mtp_partida_restaurar(const char* rom, const char* copia, MtpPartidaResultado* out);

// Carpeta de las copias de seguridad (UTF-8). Valida hasta la siguiente llamada.
const char* mtp_partida_carpeta_copias(void);

#ifdef __cplusplus
}
#endif

#endif  // MTP_PARTIDAS_H
