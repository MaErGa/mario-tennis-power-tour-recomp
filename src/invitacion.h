// invitacion.h — jugar online por código de invitación, SIN servidor.
//
// Lo implementa src/invitacion.cpp; lo usa la pantalla «Jugar online» del menú de arranque
// (parches/recomp-ui-0007-*.patch) y main.cpp (que le pide los argumentos de red al terminar
// el menú). Es C puro a propósito: el menú es C++ de otro proyecto y solo necesita estas
// funciones y estas estructuras.
//
// Cómo funciona (no hay lobby, cuenta ni servidor nuestro):
//   1. La persona que invita (anfitrión) abre un puerto UDP, le pregunta a un servidor STUN
//      público (por defecto el de Google y el de Cloudflare) «¿desde qué dirección me ves?» y
//      con eso construye un CÓDIGO DE INVITACIÓN (su dirección pública y la de su red local, más
//      un número aleatorio). Se lo pasa a su amigo por el chat que quiera.
//   2. El amigo (invitado) lo pega, hace lo mismo con su puerto y obtiene un CÓDIGO DE RESPUESTA
//      que le devuelve al anfitrión.
//   3. Con los dos códigos cada uno conoce la dirección del otro: ambos se envían paquetes UDP a
//      la vez («perforado de NAT») y, cuando los dos se han oído, el juego arranca en modo
//      «cable link por red» entre las dos direcciones.
// El servidor STUN solo ve «alguien con esta IP preguntó su dirección»; no recibe códigos, ni
// nombres, ni partidas. No funciona con algunas redes (NAT simétrico, CGNAT de algunas
// operadoras): en ese caso se avisa.
#ifndef MTP_INVITACION_H
#define MTP_INVITACION_H

#ifdef __cplusplus
extern "C" {
#endif

// Estados (MtpInvInfo.estado).
enum {
    MTP_INV_REPOSO = 0,              // no hay nada en marcha
    MTP_INV_PREPARANDO = 1,          // consultando la dirección pública (STUN)
    MTP_INV_ESPERANDO_RESPUESTA = 2, // anfitrión: el código de invitación está listo
    MTP_INV_ESPERANDO_AMIGO = 3,     // invitado: el código de respuesta está listo
    MTP_INV_CONECTANDO = 4,          // intercambiando paquetes con el otro equipo
    MTP_INV_CONECTADO = 5,           // listo: se puede arrancar la partida
    MTP_INV_ERROR = 6                // ver MtpInvInfo.error
};

// Roles (MtpInvInfo.rol).
enum { MTP_INV_NINGUNO = 0, MTP_INV_ANFITRION = 1, MTP_INV_INVITADO = 2 };

// Códigos de error (MtpInvInfo.error y el valor devuelto por las funciones de comprobar/unirse/
// responder).
enum {
    MTP_INV_OK = 0,
    MTP_INV_ERR_CODIGO = 1,     // el código está mal escrito o incompleto
    MTP_INV_ERR_TIPO = 2,       // se ha pegado un código de respuesta donde iba el de invitación (o al revés)
    MTP_INV_ERR_VERSION = 3,    // el amigo tiene otra versión del programa (o de la ROM/código generado)
    MTP_INV_ERR_OTRA_SALA = 4,  // el código de respuesta no es de esta sala
    MTP_INV_ERR_SIN_RED = 5,    // no se pudo abrir un puerto UDP
    MTP_INV_ERR_TIEMPO = 6,     // no se consiguió conectar a tiempo
    MTP_INV_ERR_NO_DISPONIBLE = 7, // esta compilación no incluye el juego en red
    MTP_INV_ERR_OCUPADO = 8     // ya hay una sala en marcha
};

typedef struct MtpInvInfo {
    int estado;               // MTP_INV_*
    int rol;                  // MTP_INV_ANFITRION / MTP_INV_INVITADO / MTP_INV_NINGUNO
    int error;                // MTP_INV_ERR_* (solo con estado == MTP_INV_ERROR; 0 si no)
    int segundos;             // segundos transcurridos en el estado actual
    int sin_internet;         // 1: no se pudo preguntar la dirección pública; el código solo vale en la misma red local
    int nat_simetrico;        // 1: la red de esta persona probablemente no permite la conexión directa
    int amigo_nat_simetrico;  // 1: lo mismo, pero lo dijo el código del amigo
    int codigo_nuevo;         // se suma 1 cada vez que el código de invitación cambia (la dirección pública cambió)
    char codigo[128];         // código que hay que enseñar y copiar ("" si todavía no hay)
    char par[64];             // dirección del otro equipo ("a.b.c.d:puerto") cuando está conectado, si no ""
    char nombre_amigo[40];    // cómo se llama el amigo: el apodo que le hayas puesto, o el nombre que él anunció ("" si ninguno)
} MtpInvInfo;

// 1 si esta compilación incluye el juego en red (MTP_NETPLAY); si no, 0.
int mtp_inv_disponible(void);

// Abre una sala como anfitrión: prepara el código de invitación en segundo plano.
// Devuelve MTP_INV_OK, MTP_INV_ERR_OCUPADO o MTP_INV_ERR_NO_DISPONIBLE.
int mtp_inv_crear(void);

// Comprueba un código sin hacer nada más. `tipo`: 0 = invitación, 1 = respuesta. Devuelve
// MTP_INV_OK o el motivo. Admite minúsculas, espacios y guiones de más.
int mtp_inv_comprobar(const char* codigo, int tipo);

// Invitado: usa el código de invitación del anfitrión y prepara el código de respuesta.
// Devuelve MTP_INV_OK o el motivo por el que se rechaza (la sala no arranca).
int mtp_inv_unirse(const char* codigo_invitacion);

// Anfitrión: usa el código de respuesta del invitado y empieza a conectar.
int mtp_inv_responder(const char* codigo_respuesta);

// Lo que está pasando ahora (se puede llamar en cada fotograma).
void mtp_inv_estado(MtpInvInfo* out);

// Cancela lo que haya en marcha y lo deja todo en reposo. Si ya estaba conectado, el puerto
// se libera (no se podrá arrancar la partida).
void mtp_inv_cancelar(void);

// Con la sala conectada: escribe en `out` los argumentos de línea de órdenes del juego en red
// (--netplay-bind, --netplay-peer, --netplay-seat, --netplay-session), uno por línea. Devuelve
// cuántos bytes escribió (0 si no hay una sala conectada). Después de esto la sala vuelve a
// reposo: el juego en red es quien usa ya el puerto.
int mtp_inv_argumentos(char* out, int tam);

// --- Nombres para reconocerse (no el del personaje del juego) ----------------------------------
// Tu nombre viaja en los paquetes de conexión: tu amigo lo ve (MtpInvInfo.nombre_amigo) en cuanto se
// oyen, y la partida lo enseña en el título de la ventana y en un rótulo al empezar. Se limpia:
// UTF-8 válido, sin caracteres de control ni invisibles, máximo 24 bytes (unas 20 letras).
// Escribe en `out` el nombre guardado (config.ini, [Online] Nombre) o "" si no hay.
void mtp_inv_nombre_propio(char* out, int tam);
// Cambia tu nombre; con `guardar` distinto de 0 también se recuerda para la próxima vez.
void mtp_inv_fijar_nombre_propio(const char* nombre, int guardar);
// Apodo que solo ves tú para tu amigo (vale para la sala en curso y la partida; no se guarda).
// "" = usar el nombre que él anunció.
void mtp_inv_fijar_apodo_amigo(const char* apodo);

// --- Solo para las pruebas ----------------------------------------------------------------
// Texto de un código de prueba con una dirección pública y otra local dadas (no abre nada).
// Devuelve 0 si cupo en `out`.
int mtp_inv_prueba_codigo(int tipo, unsigned int nonce, unsigned int ip_publica, int puerto_publico,
                          unsigned int ip_local, int puerto_local, int nat_simetrico, char* out, int tam);

#ifdef __cplusplus
}
#endif

#endif  // MTP_INVITACION_H
