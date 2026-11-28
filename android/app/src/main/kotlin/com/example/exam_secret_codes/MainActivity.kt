package com.example.exam_secret_codes

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.os.Handler
import android.provider.Settings
import android.os.Build
import android.util.Base64
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import org.json.JSONObject
import android.os.Looper
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.multipdf.LayerUtility
import com.tom_roush.pdfbox.util.Matrix
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.exam_secret_codes/document_pdf"
    private val excelPickerRequestCode = 7412
    private var pendingExcelPickerResult: MethodChannel.Result? = null
    private val licenseChannelName = "com.example.exam_secret_codes/license"
    private val legacySecretSalt = "EXAM_MAKER_SECURE_SALT_2026_@ALBAETHEE"
    private val licensePublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvlaA/c3IBKEro+rvm6hjYFCbUmB3xNwpN6FlqUw1RtuFB37u0blR37TmMxB/yX0plEEGjWDeH3+nvG2/KnVaBYXN/6qwc+bSHcT5nzmRK0zMfFutX302Ad4f9l8BoTrv83p7kxIBoF0LoVi090FRrWRtHRK8fFysfOcnp9hsKJJ1HH8gHf9YtuMmIkBml3RL1en9zgesQtkQKaDgHE1h1jJSLCiFl6/t/xf+z4bqS/WVl2fVYcOENl+9LV6mFmNunPmXVj9SlTQ/rKU0SEUoy41kj5ZFfG8uCMs/7eBLPLCMlIP2F0pp88u4IMkNyYXViry4TpytkQawAvddF3oXiwIDAQAB"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, licenseChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceId" -> {
                        try {
                            result.success(getLegacyCompatibleDeviceId())
                        } catch (e: Exception) {
                            result.error("DEVICE_ID_FAILED", e.message, null)
                        }
                    }
                    "verifyLegacyKey" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrBlank()) {
                            result.success(mapOf("valid" to false))
                        } else {
                            try {
                                result.success(verifyLegacyKey(key))
                            } catch (_: Exception) {
                                result.success(mapOf("valid" to false))
                            }
                        }
                    }
                    "verifyLicense" -> {
                        val token = call.argument<String>("token")
                        if (token.isNullOrBlank()) {
                            result.success(mapOf("valid" to false))
                        } else {
                            try {
                                result.success(verifyLicenseToken(token))
                            } catch (_: Exception) {
                                result.success(mapOf("valid" to false))
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickExcelDocument" -> {
                        if (pendingExcelPickerResult != null) {
                            result.error("PICKER_BUSY", "هناك عملية اختيار ملف جارية.", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                "application/vnd.ms-excel.sheet.macroEnabled.12",
                                "application/vnd.ms-excel",
                                "application/octet-stream",
                                "application/zip"
                            ))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        pendingExcelPickerResult = result
                        try {
                            startActivityForResult(intent, excelPickerRequestCode)
                        } catch (e: Exception) {
                            pendingExcelPickerResult = null
                            result.error("PICKER_FAILED", e.message ?: "تعذر فتح منتقي الملفات.", null)
                        }
                        return@setMethodCallHandler
                    }
                    "readExcelDocument" -> {
                        val uriText = call.argument<String>("uri")
                        if (uriText.isNullOrBlank()) {
                            result.error("INVALID_URI", "مرجع ملف Excel غير صالح.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bytes = contentResolver.openInputStream(Uri.parse(uriText))?.use { it.readBytes() }
                                ?: throw IllegalStateException("تعذر فتح الملف للقراءة.")
                            if (bytes.isEmpty()) throw IllegalStateException("ملف Excel الأصلي فارغ.")
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("EXCEL_READ_FAILED", e.message ?: "تعذرت قراءة ملف Excel الأصلي.", null)
                        }
                        return@setMethodCallHandler
                    }
                    "createStudentPdf" -> Unit
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }

                val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                val sourcePath = arguments["sourcePath"] as? String
                val outputPath = arguments["outputPath"] as? String
                val rawStudents = arguments["students"] as? List<*> ?: emptyList<Any?>()
                val students: List<Map<String, String>> = rawStudents.mapNotNull { item ->
                    val map = item as? Map<*, *> ?: return@mapNotNull null
                    map.entries.associate { entry ->
                        entry.key.toString() to (entry.value?.toString() ?: "")
                    }
                }
                val subjectCode = (arguments["subjectCode"] as? Number)?.toInt() ?: 1
                val studentDataOnLastPage = arguments["studentDataOnLastPage"] as? Boolean ?: false
                val cropTopFraction = (arguments["cropTopFraction"] as? Number)?.toFloat() ?: 0f
                val cropBottomFraction = (arguments["cropBottomFraction"] as? Number)?.toFloat() ?: 0f

                if (sourcePath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "مسار ملف PDF غير صالح.", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        createStudentPdf(
                            sourcePath = sourcePath,
                            outputPath = outputPath,
                            students = students,
                            subjectCode = subjectCode,
                            studentDataOnLastPage = studentDataOnLastPage,
                            cropTopFraction = cropTopFraction,
                            cropBottomFraction = cropBottomFraction
                        )
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputPath)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("PDF_PROCESSING_FAILED", e.message ?: "تعذرت معالجة ملف PDF.", null)
                        }
                    }
                }.start()
            }
    }


    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != excelPickerRequestCode) return

        val callback = pendingExcelPickerResult
        pendingExcelPickerResult = null
        if (callback == null) return
        if (resultCode != RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }

        val uri = data.data!!
        val grantedFlags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (grantedFlags == 0) {
            callback.error(
                "EXCEL_READ_PERMISSION_MISSING",
                "لم يمنح مزود الملفات صلاحية قراءة الملف المحدد. اختر الملف من مدير ملفات موثوق.",
                null
            )
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, grantedFlags)
        } catch (_: Exception) {
            // Some providers grant access for the current app session only.
        }

        var displayName = "workbook.xlsx"
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) displayName = cursor.getString(index) ?: displayName
            }
        } catch (_: Exception) {
        } finally {
            cursor?.close()
        }

        val extension = displayName.substringAfterLast('.', "").lowercase()
        if (extension != "xlsx" && extension != "xlsm") {
            callback.error(
                "UNSUPPORTED_EXCEL_FORMAT",
                "الصيغة المدعومة هي XLSX أو XLSM.",
                null
            )
            return
        }

        callback.success(mapOf("uri" to uri.toString(), "name" to displayName))
    }

    // device_info_plus AndroidInfo.id maps to android.os.Build.ID.
    // This reproduces the exact fingerprint used by exam_maker_app.
    private fun getLegacyCompatibleDeviceId(): String {
        val rawId = Build.ID.takeIf { it.isNotEmpty() }
            ?: "${Build.BRAND}_${Build.MODEL}_${Build.FINGERPRINT}"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(rawId.toByteArray(Charsets.UTF_8))
        val hex = digest.joinToString("") { "%02X".format(it) }
        return "${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}"
    }

    // Retain support for RSA licenses already issued with the previous Android ID.
    private fun getStableDeviceId(): String {
        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?: throw IllegalStateException("Android ID is unavailable")
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(androidId.toByteArray(Charsets.UTF_8))
        val hex = digest.joinToString("") { "%02X".format(it) }.take(12)
        return "${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}"
    }

    private fun verifyLegacyKey(enteredKey: String): Map<String, Any?> {
        val cleanDevice = getLegacyCompatibleDeviceId().replace("-", "").trim().uppercase()
        val cleanKey = enteredKey.trim().uppercase()

        val fullCombined = "$cleanDevice:FULL:$legacySecretSalt"
        val fullHash = MessageDigest.getInstance("SHA-256")
            .digest(fullCombined.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02X".format(it) }
        val expectedFull = "FL-${fullHash.substring(0, 4)}-${fullHash.substring(4, 8)}-${fullHash.substring(8, 12)}"
        if (cleanKey == expectedFull) return mapOf("valid" to true, "type" to "full")

        val trialCombined = "$cleanDevice:TRIAL:$legacySecretSalt"
        val trialHash = MessageDigest.getInstance("SHA-256")
            .digest(trialCombined.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02X".format(it) }
        val expectedTrial = "TR-${trialHash.substring(0, 4)}-${trialHash.substring(4, 8)}-${trialHash.substring(8, 12)}"
        if (cleanKey == expectedTrial) return mapOf("valid" to true, "type" to "trial")

        return mapOf("valid" to false)
    }

    private fun verifyLicenseToken(token: String): Map<String, Any?> {
        val parts = token.trim().split(".")
        if (parts.size != 2) return mapOf("valid" to false)

        val decoderFlags = Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
        val payloadBytes = Base64.decode(parts[0], decoderFlags)
        val signatureBytes = Base64.decode(parts[1], decoderFlags)

        val publicBytes = Base64.decode(licensePublicKey, Base64.DEFAULT)
        val publicKey = KeyFactory.getInstance("RSA")
            .generatePublic(X509EncodedKeySpec(publicBytes))
        val verifier = Signature.getInstance("SHA256withRSA")
        verifier.initVerify(publicKey)
        verifier.update(payloadBytes)
        if (!verifier.verify(signatureBytes)) return mapOf("valid" to false)

        val payload = JSONObject(String(payloadBytes, Charsets.UTF_8))
        if (payload.optInt("v") != 1 ||
            payload.optString("app") != "exam_secret_codes" ||
            (payload.optString("device") != getStableDeviceId() &&
                payload.optString("device") != getLegacyCompatibleDeviceId())
        ) return mapOf("valid" to false)

        val type = payload.optString("type")
        val issuedAt = payload.optLong("issuedAt", 0L)
        val expiresAt = payload.optLong("expiresAt", 0L)
        val now = System.currentTimeMillis() / 1000L
        if (issuedAt <= 0L) return mapOf("valid" to false)

        return when (type) {
            "full" -> mapOf("valid" to true, "type" to "full", "expiresAt" to 0L)
            "trial" -> {
                val expectedDuration = 30L * 24L * 60L * 60L
                val duration = expiresAt - issuedAt
                val valid = issuedAt <= now + 300L &&
                    duration in (expectedDuration - 300L)..(expectedDuration + 300L) &&
                    now < expiresAt
                mapOf("valid" to valid, "type" to "trial", "expiresAt" to expiresAt)
            }
            else -> mapOf("valid" to false)
        }
    }

    private fun createStudentPdf(
        sourcePath: String,
        outputPath: String,
        students: List<Map<String, String>>,
        subjectCode: Int,
        studentDataOnLastPage: Boolean,
        cropTopFraction: Float,
        cropBottomFraction: Float
    ) {
        PDFBoxResourceLoader.init(applicationContext)

        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) throw IllegalArgumentException("ملف PDF الأصلي غير موجود.")

        PDDocument.load(sourceFile).use { source ->
            if (source.numberOfPages == 0) throw IllegalArgumentException("ملف PDF لا يحتوي على صفحات.")

            PDDocument().use { output ->
                val layerUtility = LayerUtility(output)
                val font = PDType0Font.load(
                    output,
                    assets.open("flutter_assets/assets/fonts/Amiri-Regular.ttf")
                )
                // Import each original PDF page once, then reuse its vector form for every student.
                val sourceForms = (0 until source.numberOfPages).map { pageIndex ->
                    layerUtility.importPageAsForm(source, source.getPage(pageIndex))
                }

                val copies: List<Map<String, String>> =
                    if (students.isEmpty()) listOf(emptyMap()) else students

                for (student in copies) {
                    for (pageIndex in 0 until source.numberOfPages) {
                        val sourcePage = source.getPage(pageIndex)
                        val form = sourceForms[pageIndex]
                        val page = PDPage(PDRectangle.A4)
                        output.addPage(page)

                        val pageWidth = PDRectangle.A4.width
                        val pageHeight = PDRectangle.A4.height
                        val studentDataPageIndex = if (studentDataOnLastPage) source.numberOfPages - 1 else 0
                        val hasStudentData = !student["seatNo"].isNullOrBlank() && pageIndex == studentDataPageIndex

                        // Reserve exactly 1 cm for student details and 3 cm for
                        // the subject code, QR and grade box on the selected data page.
                        val topReserve = if (hasStudentData) 28.35f else 0f
                        val bottomReserve = if (hasStudentData) 85.04f else 0f
                        val sideMargin = 20f
                        val contentWidth = pageWidth - (sideMargin * 2f)
                        val contentHeight = pageHeight - topReserve - bottomReserve

                        val box = form.bBox ?: sourcePage.mediaBox
                        val sourceWidth = box.width.coerceAtLeast(1f)
                        val sourceHeight = box.height.coerceAtLeast(1f)

                        // Crop only the first imported page; subsequent pages remain complete.
                        val safeTopFraction = (if (pageIndex == 0) cropTopFraction else 0f)
                            .coerceIn(0f, 0.99f)
                        val safeBottomFraction = (if (pageIndex == 0) cropBottomFraction else 0f)
                            .coerceIn(0f, 0.99f)
                        val effectiveBottomFraction =
                            minOf(safeBottomFraction, 0.99f - safeTopFraction)
                        val topCrop = sourceHeight * safeTopFraction
                        val bottomCrop = sourceHeight * effectiveBottomFraction
                        val visibleHeight = (sourceHeight - topCrop - bottomCrop).coerceAtLeast(1f)

                        // Stretch the retained content on the first source page (when cropped),
                        // or the selected student-data page, across its available rectangle.
                        val scaleX = contentWidth / sourceWidth
                        val scaleY = contentHeight / visibleHeight
                        val offsetX = sideMargin
                        val offsetY = bottomReserve
                        val boxLeft = box.lowerLeftX
                        val boxBottom = box.lowerLeftY

                        PDPageContentStream(output, page).use { stream ->
                            stream.saveGraphicsState()
                            stream.transform(
                                Matrix(
                                    scaleX, 0f, 0f, scaleY,
                                    offsetX - (boxLeft * scaleX),
                                    offsetY - ((boxBottom + bottomCrop) * scaleY)
                                )
                            )
                            stream.addRect(
                                boxLeft,
                                boxBottom + bottomCrop,
                                sourceWidth,
                                visibleHeight
                            )
                            stream.clip()
                            stream.drawForm(form)
                            stream.restoreGraphicsState()

                            if (hasStudentData) {
                                val name = student["name"]?.toString().orEmpty()
                                val seat = student["seatNo"]?.toString().orEmpty()
                                val secret = student["secretCode"]?.toString().orEmpty()

                                drawArabicText(
                                    output, stream, "اسم الطالب: $name",
                                    pageWidth - 284f, pageHeight - 29f, 260f, 10.5f,
                                    Layout.Alignment.ALIGN_NORMAL
                                )
                                drawArabicText(
                                    output, stream, "رقم الجلوس: [ $seat ]",
                                    24f, pageHeight - 29f, 210f, 10.5f,
                                    Layout.Alignment.ALIGN_OPPOSITE
                                )

                                val subjectText = subjectCode.toString()
                                // Keep the printed subject/period code in a high-contrast square
                                // matching the QR dimensions, immediately to its right.
                                val gradeBoxX = 20f
                                val qrX = gradeBoxX + 55f + 10f
                                val codeBoxSize = 38f
                                val codeBoxX = qrX + codeBoxSize + 8f
                                val codeBoxY = 12f

                                if (secret.isNotBlank()) {
                                    val qrBitmap = createQrBitmap(secret)
                                    val qrImage = LosslessFactory.createFromImage(output, qrBitmap)
                                    stream.drawImage(qrImage, qrX, codeBoxY, codeBoxSize, codeBoxSize)
                                    qrBitmap.recycle()
                                }

                                // White paper remains the box interior; use a strong black outline.
                                stream.setStrokingColor(0, 0, 0)
                                stream.setLineWidth(2.2f)
                                stream.addRect(codeBoxX, codeBoxY, codeBoxSize, codeBoxSize)
                                stream.stroke()

                                // Center the dark code in the square and lower it slightly
                                // from its previous baseline to align visually with the box.
                                val maxTextWidth = codeBoxSize - 7f
                                val naturalTextWidth = font.getStringWidth(subjectText) / 1000f * 22f
                                val codeFontSize = if (naturalTextWidth > maxTextWidth) {
                                    22f * maxTextWidth / naturalTextWidth
                                } else {
                                    22f
                                }
                                val textWidth = font.getStringWidth(subjectText) / 1000f * codeFontSize
                                val textX = codeBoxX + (codeBoxSize - textWidth) / 2f
                                val textY = codeBoxY + (codeBoxSize - codeFontSize * 0.70f) / 2f
                                stream.setNonStrokingColor(0, 0, 0)
                                drawText(stream, font, subjectText, textX, textY, codeFontSize)

                                stream.addRect(gradeBoxX, 10f, 55f, 45f)
                                stream.stroke()
                            }
                        }
                    }
                }

                File(outputPath).parentFile?.mkdirs()
                output.save(File(outputPath))
            }
        }
    }

    private fun createQrBitmap(value: String): Bitmap {
        val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, 240, 240)
        val bitmap = Bitmap.createBitmap(240, 240, Bitmap.Config.ARGB_8888)
        for (x in 0 until 240) {
            for (y in 0 until 240) {
                bitmap.setPixel(
                    x,
                    y,
                    if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
                )
            }
        }
        return bitmap
    }

    private fun drawArabicText(
        document: PDDocument,
        stream: PDPageContentStream,
        text: String,
        x: Float,
        y: Float,
        width: Float,
        fontSize: Float,
        alignment: Layout.Alignment
    ) {
        if (text.isBlank()) return

        val renderScale = 3
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.BLACK
            textSize = fontSize * renderScale
            typeface = Typeface.createFromAsset(
                assets,
                "flutter_assets/assets/fonts/Amiri-Regular.ttf"
            )
        }

        val layout = StaticLayout(
            text,
            paint,
            (width * renderScale).toInt().coerceAtLeast(1),
            alignment,
            1.0f,
            0.0f,
            false
        )
        val bitmap = Bitmap.createBitmap(
            (width * renderScale).toInt().coerceAtLeast(1),
            layout.height.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        layout.draw(canvas)

        val image = LosslessFactory.createFromImage(document, bitmap)
        stream.drawImage(
            image,
            x,
            y,
            width,
            layout.height.toFloat() / renderScale
        )
        bitmap.recycle()
    }

    private fun drawRightText(
        stream: PDPageContentStream,
        font: PDType0Font,
        text: String,
        rightX: Float,
        y: Float,
        size: Float
    ) {
        val width = font.getStringWidth(text) / 1000f * size
        drawText(stream, font, text, rightX - width, y, size)
    }

    private fun drawText(
        stream: PDPageContentStream,
        font: PDType0Font,
        text: String,
        x: Float,
        y: Float,
        size: Float
    ) {
        stream.beginText()
        stream.setFont(font, size)
        stream.newLineAtOffset(x, y)
        stream.showText(text)
        stream.endText()
    }
}
