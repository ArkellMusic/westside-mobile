# Instalar WESTSIDE LEGACY en el iPhone desde Windows

Esta guía es para instalar la app en un iPhone 16e usando solo un PC con Windows, sin Mac.

> **Aviso:** el autor de esta guía no ha podido probar la instalación en un dispositivo real. Los pasos están escritos según la documentación de las herramientas, pero pueden cambiar con las actualizaciones de iOS, iTunes o Sideloadly.
>
> El fichero `.ipa` que genera GitHub Actions **no está firmado**. No se puede instalar tal cual: Sideloadly lo firma con tu Apple ID durante la instalación.

---

## Parte 1. Conseguir el fichero .ipa

Hay dos formas. Prueba primero la **opción A**.

### Opción A: desde GitHub Actions (PC)

1. Abre el repositorio en el navegador: [github.com/ArkellMusic/westside-mobile](https://github.com/ArkellMusic/westside-mobile)
2. Entra en la pestaña **Actions**.
3. En la lista de la izquierda, busca el flujo **Compilar IPA iOS**.
4. Abre la ejecución más reciente que tenga una marca verde (**successful**). Las que tienen una cruz roja han fallado y no sirven.
5. Baja hasta la sección **Artifacts**.
6. Pulsa **WestsideLegacy-ipa**. Se descargará un fichero `.zip`.
7. Descomprime el `.zip` (botón derecho > **Extraer todo**).
8. Dentro encontrarás **WestsideLegacy.ipa**. Ese es el fichero que necesitas.

### Opción B: desde la Release (en el iPhone)

Si la compilación también se ha publicado como **Release**, puedes descargarla directamente desde el móvil:

1. Abre en Safari: [github.com/ArkellMusic/westside-mobile](https://github.com/ArkellMusic/westside-mobile)
2. Entra en **Releases** (o en la sección de versiones).
3. Busca la Release llamada **Última compilación**.
4. Descarga el fichero **.ipa** adjunto.

> Si usas la opción B, el fichero debe pasarse después al PC para instalarlo con Sideloadly, porque Sideloadly se ejecuta en Windows. Puedes enviártelo por correo o guardarlo en iCloud Drive y descargarlo en el PC.

---

## Parte 2. Instalar el .ipa con Sideloadly (Windows)

### 2.1 Instalar iTunes e iCloud

Sideloadly necesita que iTunes e iCloud estén instalados y funcionando en el PC. **Descárgalos desde la web de Apple**, no desde Microsoft Store.

1. Entra en [apple.com](https://www.apple.com) y descarga **iTunes** para Windows.
2. Descarga **iCloud para Windows** también desde apple.com.
3. Instala los dos. Si ya tienes versiones de la Microsoft Store, desinstálalas antes.
4. Reinicia el PC.

### 2.2 Instalar Sideloadly

1. Entra en [sideloadly.io](https://sideloadly.io) y descarga la versión para Windows.
2. Instálala y ábrela.

### 2.3 Conectar el iPhone

1. Conecta el iPhone al PC con el cable USB.
2. Desbloquea el iPhone con el código.
3. Aparecerá la pregunta **¿Confiar en este ordenador?**. Pulsa **Confiar** y escribe el código del iPhone si te lo pide.

### 2.4 Firmar e instalar la app

1. En Sideloadly, arrastra el fichero **WestsideLegacy.ipa** a la ventana. También puedes pulsar el selector y elegirlo.
2. En el desplegable de dispositivo, comprueba que aparece tu iPhone.
3. Escribe tu **Apple ID** (el correo) y su contraseña.

   > Te recomendamos usar un **Apple ID secundario**, creado solo para esto, en lugar de tu cuenta principal.

4. Pulsa **Start**.
5. Si Sideloadly te pide un **código de verificación de dos factores**, mira el iPhone (o el otro dispositivo donde tengas tu Apple ID), copia el código y escríbelo en Sideloadly.
6. Espera a que la barra termine y muestre que la instalación se ha completado. La app aparecerá en la pantalla de inicio del iPhone.

---

## Parte 3. Preparar el iPhone

Hay que hacer dos cosas en el iPhone antes de abrir la app por primera vez.

### 3.1 Confiar en el perfil de desarrollador

Sin este paso, iOS no deja abrir la app.

1. Abre **Ajustes**.
2. Ve a **General** > **VPN y gestión de dispositivos**.
3. Toca el perfil de desarrollador, que lleva el correo de tu Apple ID.
4. Pulsa **Confiar** y confirma.

### 3.2 Activar el Modo de desarrollador

Desde iOS 16, hace falta activar esta opción para abrir apps instaladas con Sideloadly.

1. Abre **Ajustes**.
2. Ve a **Privacidad y seguridad**.
3. Baja hasta la sección de seguridad y pulsa **Modo de desarrollador**.
4. Activa el interruptor.
5. El iPhone se reiniciará. Después de reiniciar, confirma la activación cuando te lo pida.

Ahora ya puedes abrir **WESTSIDE LEGACY** desde la pantalla de inicio.

---

## Limitaciones de un Apple ID gratuito

Estas limitaciones son de Apple, no de la app.

- **La app deja de abrirse a los 7 días.** Hay que volver a firmarla con Sideloadly: conecta el iPhone, arrastra el .ipa y pulsa Start otra vez. Si la reinstalas sobre la misma app, los datos de partida se conservan.
- **Máximo 3 apps instaladas así a la vez** con un Apple ID gratuito.
- **Con el Apple Developer Program de pago (99 €/año)** la firma dura un año y se puede usar **TestFlight**.

---

## Solución de problemas

### No detecta el iPhone

- Usa un cable USB de datos. Algunos cables solo cargan.
- Desbloquea el iPhone y comprueba que has pulsado **Confiar** en el ordenador.
- Desinstala y vuelve a instalar **iTunes** descargándolo desde apple.com.
- Reinicia el PC y el iPhone.

### Error de Apple ID / contraseña

- Revisa que el correo y la contraseña sean exactos.
- Si tienes activada la verificación en dos pasos, usa el código que llega al dispositivo de confianza.
- Prueba a iniciar sesión en tu cuenta desde [apple.com](https://www.apple.com) para comprobar que la contraseña funciona.

### La app se cierra al abrirla

- Comprueba que el **Modo de desarrollador** está activado (Parte 3.2).
- Comprueba que has pulsado **Confiar** en el perfil de desarrollador (Parte 3.1).
- Si cambiaste de Apple ID, vuelve a instalar la app con Sideloadly.

### Caducó a los 7 días

- Es el comportamiento normal con un Apple ID gratuito. Conecta el iPhone y vuelve a firmar la app con Sideloadly (Parte 2.4).
