package com.v1ki.pokesurvivor;

import android.os.Build;
import android.os.Bundle;
import android.view.Display;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebView;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.BridgeActivity;

/**
 * PokéSurvivor como app: pantalla completa de verdad, la pantalla no se apaga
 * mientras juegas, la mayor tasa de refresco del móvil (90/120 Hz si la hay;
 * el juego usa el tiempo real de cada fotograma, así que no va más rápido) y
 * el sonido suena sin tener que tocar antes la pantalla.
 */
public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        float hz = preferHighestRefreshRate();
        WebView web = getBridge().getWebView();
        requestFrameRate(web, hz);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        // Sin rebote al llegar al borde ni barras de desplazamiento: es un juego, no una web.
        web.setOverScrollMode(WebView.OVER_SCROLL_NEVER);
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        hideSystemBars();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        // Al volver a la app (o tras deslizar para ver las barras) se vuelven a esconder.
        if (hasFocus) hideSystemBars();
    }

    /** Barras de estado y de navegación escondidas; se ven un momento deslizando desde el borde. */
    private void hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat bars = WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        bars.hide(WindowInsetsCompat.Type.systemBars());
        bars.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
    }

    /** Elige el modo de pantalla con más hercios (misma resolución). → esos hercios */
    private float preferHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return 60f;
        Display display = getWindowManager().getDefaultDisplay();
        Display.Mode current = display.getMode();
        Display.Mode best = current;
        for (Display.Mode m : display.getSupportedModes()) {
            if (m.getPhysicalWidth() == current.getPhysicalWidth()
                    && m.getPhysicalHeight() == current.getPhysicalHeight()
                    && m.getRefreshRate() > best.getRefreshRate()) {
                best = m;
            }
        }
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        lp.preferredDisplayModeId = best.getModeId();
        getWindow().setAttributes(lp);
        return best.getRefreshRate();
    }

    /**
     * Android 15+ decide los hercios según lo que pide cada vista: la WebView
     * cuenta como contenido "normal" y se queda en 60 Hz aunque la pantalla
     * esté a 120. Se le piden los hercios de la pantalla (View.setRequestedFrameRate,
     * API 35; por reflexión porque Capacitor 6 compila con la API 34).
     */
    private void requestFrameRate(View view, float hz) {
        if (Build.VERSION.SDK_INT < 35) return;
        try {
            View.class.getMethod("setRequestedFrameRate", float.class).invoke(view, hz);
        } catch (ReflectiveOperationException ignored) {
            // Sin ese método: se queda con lo que decida el sistema.
        }
    }
}
