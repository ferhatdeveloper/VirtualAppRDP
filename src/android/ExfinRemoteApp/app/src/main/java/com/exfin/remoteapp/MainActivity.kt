package com.exfin.remoteapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.exfin.remoteapp.ui.WizardScreen
import com.exfin.remoteapp.ui.theme.ExfinTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ExfinTheme {
                WizardScreen()
            }
        }
    }
}
