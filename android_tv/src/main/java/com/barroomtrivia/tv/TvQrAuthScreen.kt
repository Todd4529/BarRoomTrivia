package com.barroomtrivia.tv

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.EnumMap

/**
 * UI State for Android TV QR Code Authentication Flow
 */
sealed class TvAuthState {
    object Loading : TvAuthState()
    data class DisplayQr(
        val deviceToken: String,
        val sessionToken: String,
        val userCode: String,
        val verificationUrl: String,
        val qrBitmap: Bitmap,
        val remainingSeconds: Int
    ) : TvAuthState()
    data class Authenticated(
        val userId: String,
        val displayName: String?,
        val sessionToken: String
    ) : TvAuthState()
    data class Expired(val message: String) : TvAuthState()
    data class Error(val errorMessage: String) : TvAuthState()
}

/**
 * Android TV QR Code Authentication Screen in Jetpack Compose.
 *
 * 1. Calls GET /auth/device/code on initialization to generate short-lived device token & verification URL.
 * 2. Renders the URL as a high-contrast QR code using ZXing.
 * 3. Polls GET /auth/device/status every 4 seconds until verified or expired.
 * 4. Navigates to Host/TV Dashboard via [onAuthSuccess] callback when paired.
 */
@Composable
fun TvQrAuthScreen(
    backendBaseUrl: String = "https://api.barroomstrivia.com",
    onAuthSuccess: (userId: String, sessionToken: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var authState by remember { mutableStateOf<TvAuthState>(TvAuthState.Loading) }
    var refreshTrigger by remember { mutableStateOf(0) }

    // 1. Initial Device Code Generation
    LaunchedEffect(refreshTrigger) {
        authState = TvAuthState.Loading
        try {
            val response = withContext(Dispatchers.IO) {
                fetchDeviceCode(backendBaseUrl)
            }

            if (response != null && response.optBoolean("success", false)) {
                val deviceToken = response.getString("device_token")
                val sessionToken = response.getString("session_token")
                val userCode = response.getString("user_code")
                val verificationUrl = response.getString("verification_url")
                val expiresIn = response.optInt("expires_in", 300)

                val qrBitmap = withContext(Dispatchers.Default) {
                    generateQrBitmap(verificationUrl, 512)
                }

                authState = TvAuthState.DisplayQr(
                    deviceToken = deviceToken,
                    sessionToken = sessionToken,
                    userCode = userCode,
                    verificationUrl = verificationUrl,
                    qrBitmap = qrBitmap,
                    remainingSeconds = expiresIn
                )
            } else {
                authState = TvAuthState.Error("Failed to initialize pairing session with backend.")
            }
        } catch (e: Exception) {
            authState = TvAuthState.Error("Network error: ${e.localizedMessage ?: "Unknown error"}")
        }
    }

    // 2. Status Polling Loop every 4 seconds + Expiration Countdown
    LaunchedEffect(authState) {
        val currentState = authState
        if (currentState is TvAuthState.DisplayQr) {
            val deviceToken = currentState.deviceToken
            var secondsLeft = currentState.remainingSeconds

            while (isActive && secondsLeft > 0) {
                delay(4000L) // Poll status every 4 seconds
                secondsLeft -= 4

                val statusResult = withContext(Dispatchers.IO) {
                    pollDeviceStatus(backendBaseUrl, deviceToken)
                }

                if (statusResult != null) {
                    val status = statusResult.optString("status")
                    if (status == "verified") {
                        val userId = statusResult.getString("user_id")
                        val userInfo = statusResult.optJSONObject("user_info")
                        val displayName = userInfo?.optString("email") ?: "Trivia Host"
                        val sessionToken = statusResult.optString("session_token", currentState.sessionToken)

                        authState = TvAuthState.Authenticated(userId, displayName, sessionToken)
                        delay(1200L)
                        onAuthSuccess(userId, sessionToken)
                        break
                    } else if (status == "expired") {
                        authState = TvAuthState.Expired("Pairing code has expired. Please refresh for a new code.")
                        break
                    }
                }

                // Update countdown seconds
                if (authState is TvAuthState.DisplayQr) {
                    val updated = authState as TvAuthState.DisplayQr
                    authState = updated.copy(remainingSeconds = maxOf(0, secondsLeft))
                }
            }

            if (secondsLeft <= 0 && authState is TvAuthState.DisplayQr) {
                authState = TvAuthState.Expired("QR code timed out. Generate a fresh code to connect.")
            }
        }
    }

    // 3. UI Layout (10-foot TV experience)
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(Color(0xFF0F172A), Color(0xFF020617))
                )
            )
            .padding(48.dp),
        contentAlignment = Alignment.Center
    ) {
        when (val state = authState) {
            is TvAuthState.Loading -> {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    CircularProgressIndicator(
                        color = Color(0xFF00F0FF),
                        strokeWidth = 6.dp,
                        modifier = Modifier.size(72.dp)
                    )
                    Spacer(modifier = Modifier.height(24.dp))
                    Text(
                        text = "Generating TV Pairing Code...",
                        color = Color.White,
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            is TvAuthState.DisplayQr -> {
                TvDisplayQrContent(
                    state = state,
                    onRefresh = { refreshTrigger++ }
                )
            }

            is TvAuthState.Authenticated -> {
                TvAuthenticatedContent(state = state)
            }

            is TvAuthState.Expired -> {
                TvErrorStateContent(
                    title = "Code Expired",
                    message = state.message,
                    buttonLabel = "Generate New QR Code",
                    onRetry = { refreshTrigger++ }
                )
            }

            is TvAuthState.Error -> {
                TvErrorStateContent(
                    title = "Connection Error",
                    message = state.errorMessage,
                    buttonLabel = "Try Again",
                    onRetry = { refreshTrigger++ }
                )
            }
        }
    }
}

/**
 * QR Code & TV Pairing Instructions Display
 */
@Composable
private fun TvDisplayQrContent(
    state: TvAuthState.DisplayQr,
    onRefresh: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(0.92f),
        horizontalArrangement = Arrangement.spacedBy(56.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Left Column: High-contrast QR Code in Neon Frame
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.weight(1.1f)
        ) {
            Box(
                modifier = Modifier
                    .shadow(elevation = 28.dp, shape = RoundedCornerShape(28.dp), spotColor = Color(0xFF00F0FF))
                    .clip(RoundedCornerShape(28.dp))
                    .background(Color.White)
                    .border(width = 4.dp, color = Color(0xFF00F0FF), shape = RoundedCornerShape(28.dp))
                    .padding(20.dp)
            ) {
                Image(
                    bitmap = state.qrBitmap.asImageBitmap(),
                    contentDescription = "Scan to Authenticate TV",
                    modifier = Modifier.size(340.dp)
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Expiration countdown badge
            val minutes = state.remainingSeconds / 60
            val seconds = state.remainingSeconds % 60
            Surface(
                color = Color(0xFF1E293B),
                shape = RoundedCornerShape(12.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF334155))
            ) {
                Text(
                    text = "Code expires in %02d:%02d".format(minutes, seconds),
                    color = if (state.remainingSeconds < 60) Color(0xFFFF5252) else Color(0xFF94A3B8),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
        }

        // Right Column: Instructions & Direct User Code
        Column(
            modifier = Modifier.weight(1.3f),
            verticalArrangement = Arrangement.Center
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Tv,
                    contentDescription = null,
                    tint = Color(0xFF00F0FF),
                    modifier = Modifier.size(40.dp)
                )
                Spacer(modifier = Modifier.width(16.dp))
                Text(
                    text = "Connect Your Phone",
                    color = Color.White,
                    fontSize = 38.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 1.2.sp
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            InstructionStep(
                number = "1",
                title = "Scan with Phone Camera",
                subtitle = "Point your smartphone camera at the QR code on the left."
            )

            Spacer(modifier = Modifier.height(18.dp))

            InstructionStep(
                number = "2",
                title = "Authorize Host Session",
                subtitle = "Tap the link to open Bar Room Trivia and grant TV access."
            )

            Spacer(modifier = Modifier.height(28.dp))

            // Or enter manual code fallback
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xFF1E293B))
                    .border(1.dp, Color(0xFFA855F7), RoundedCornerShape(16.dp))
                    .padding(18.dp)
            ) {
                Column {
                    Text(
                        text = "OR ENTER PAIRING CODE MANUALLY:",
                        color = Color(0xFFA855F7),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = state.userCode,
                        color = Color.White,
                        fontSize = 32.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFamily = FontFamily.Monospace,
                        letterSpacing = 4.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = onRefresh,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF334155),
                    contentColor = Color.White
                ),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.focusable()
            ) {
                Icon(imageVector = Icons.Default.Refresh, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(text = "Refresh Code", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun InstructionStep(
    number: String,
    title: String,
    subtitle: String
) {
    Row(verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Color(0xFF00F0FF)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = number,
                color = Color.Black,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Column {
            Text(
                text = title,
                color = Color.White,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = subtitle,
                color = Color(0xFF94A3B8),
                fontSize = 16.sp
            )
        }
    }
}

@Composable
private fun TvAuthenticatedContent(state: TvAuthState.Authenticated) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = "Success",
            tint = Color(0xFF10B981),
            modifier = Modifier.size(96.dp)
        )
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            text = "Connected Successfully!",
            color = Color.White,
            fontSize = 36.sp,
            fontWeight = FontWeight.Black
        )
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = "Welcome, ${state.displayName ?: "Host"}. Launching Game Controls...",
            color = Color(0xFF00F0FF),
            fontSize = 22.sp,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun TvErrorStateContent(
    title: String,
    message: String,
    buttonLabel: String,
    onRetry: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = Modifier.padding(32.dp)
    ) {
        Text(
            text = title,
            color = Color(0xFFFF5252),
            fontSize = 32.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = message,
            color = Color(0xFFCBD5E1),
            fontSize = 20.sp,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(32.dp))
        Button(
            onClick = onRetry,
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF00F0FF), contentColor = Color.Black),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier
                .height(52.dp)
                .focusable()
        ) {
            Icon(imageVector = Icons.Default.Refresh, contentDescription = null)
            Spacer(modifier = Modifier.width(10.dp))
            Text(text = buttonLabel, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
    }
}

/**
 * QR Code Bitmap Generator using ZXing QRCodeWriter
 */
private fun generateQrBitmap(contents: String, size: Int): Bitmap {
    val hints = EnumMap<EncodeHintType, Any>(EncodeHintType::class.java).apply {
        put(EncodeHintType.CHARACTER_SET, "UTF-8")
        put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.H)
        put(EncodeHintType.MARGIN, 1)
    }

    val bitMatrix = QRCodeWriter().encode(contents, BarcodeFormat.QR_CODE, size, size, hints)
    val width = bitMatrix.width
    val height = bitMatrix.height
    val pixels = IntArray(width * height)

    for (y in 0 until height) {
        val offset = y * width
        for (x in 0 until width) {
            pixels[offset + x] = if (bitMatrix.get(x, y)) AndroidColor.BLACK else AndroidColor.WHITE
        }
    }

    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    return bitmap
}

/**
 * Network HTTP helper: GET /auth/device/code
 */
private fun fetchDeviceCode(backendUrl: String): JSONObject? {
    val url = URL("${backendUrl.trimEnd('/')}/auth/device/code")
    val conn = (url.openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 8000
        readTimeout = 8000
        setRequestProperty("Accept", "application/json")
    }

    return try {
        if (conn.responseCode in 200..299) {
            val reader = BufferedReader(InputStreamReader(conn.inputStream))
            val jsonString = reader.readText()
            reader.close()
            JSONObject(jsonString)
        } else {
            null
        }
    } finally {
        conn.disconnect()
    }
}

/**
 * Network HTTP helper: GET /auth/device/status?device_token=...
 */
private fun pollDeviceStatus(backendUrl: String, deviceToken: String): JSONObject? {
    val url = URL("${backendUrl.trimEnd('/')}/auth/device/status?device_token=${java.net.URLEncoder.encode(deviceToken, "UTF-8")}")
    val conn = (url.openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 5000
        readTimeout = 5000
        setRequestProperty("Accept", "application/json")
    }

    return try {
        val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
        if (stream != null) {
            val reader = BufferedReader(InputStreamReader(stream))
            val jsonString = reader.readText()
            reader.close()
            JSONObject(jsonString)
        } else {
            null
        }
    } catch (e: Exception) {
        null
    } finally {
        conn.disconnect()
    }
}
