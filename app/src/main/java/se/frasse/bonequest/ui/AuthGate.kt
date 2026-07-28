package se.frasse.bonequest

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import se.frasse.bonequest.walking.WalkingPreferences
import se.frasse.bonequest.walking.WalkingServiceController

private val FrasseCharcoal = Color(0xFF171A1C)
private val FrasseGold = Color(0xFFD9A441)
private val FrasseCream = Color(0xFFFFE8BE)
private val FrasseTeal = Color(0xFF138B8A)

private sealed interface GateState {
    data object Loading : GateState
    data object SignedOut : GateState
    data object NeedsName : GateState
    data class Ready(val profile: SessionBootstrap) : GateState
    data class Error(val message: String) : GateState
}

@Composable
fun FrasseAppRoot() {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = FrasseGold, secondary = FrasseTeal,
            background = FrasseCharcoal, surface = FrasseCharcoal,
            onPrimary = Color.Black, onBackground = FrasseCream, onSurface = FrasseCream
        )
    ) {
        val client = SupabaseProvider.clientOrNull
        if (client == null) {
            MessageScreen(stringResource(R.string.backend_missing_title),stringResource(R.string.backend_missing_body))
            return@MaterialTheme
        }
        val repository = remember(client) { AuthRepository(client) }
        val scope = rememberCoroutineScope()
        var state by remember { mutableStateOf<GateState>(GateState.Loading) }

        LaunchedEffect(repository) {
            repository.sessionStatus.collect { status ->
                state = when (status) {
                    SessionStatus.Initializing -> GateState.Loading
                    is SessionStatus.Authenticated -> runCatching { repository.loadBootstrap() }.fold(
                        onSuccess = { if (!it.onboardingComplete || it.requiresNewName) GateState.NeedsName else GateState.Ready(it) },
                        onFailure = { GateState.Error(it.message.orEmpty()) }
                    )
                    is SessionStatus.NotAuthenticated -> GateState.SignedOut
                    is SessionStatus.RefreshFailure -> GateState.SignedOut
                }
            }
        }

        LaunchedEffect(state) {
            if (state == GateState.Loading) {
                delay(20_000)
                if (state == GateState.Loading) {
                    state = GateState.Error("Inloggningen tog för lång tid. Stäng webbläsaren och försök igen.")
                }
            }
        }

        when (val current = state) {
            GateState.Loading -> LoadingScreen()
            GateState.SignedOut -> LoginScreen {
                state = GateState.Loading
                scope.launch { runCatching { repository.signInWithGoogle() }
                    .onFailure { state = GateState.Error(it.message.orEmpty()) } }
            }
            GateState.NeedsName -> NameScreen { name ->
                state = GateState.Loading
                scope.launch { runCatching { repository.completeProfile(name) }.fold(
                    onSuccess = { state = GateState.Ready(it) },
                    onFailure = { state = GateState.Error(it.message.orEmpty()) }
                ) }
            }
            is GateState.Ready -> {
                StartWalkingModeIfEnabled()
                GameScreen(current.profile)
            }
            is GateState.Error -> MessageScreen(
                stringResource(R.string.login_error),
                current.message.ifBlank { stringResource(R.string.login_error) },
                stringResource(R.string.login_google)
            ) { state = GateState.SignedOut }
        }
    }
}

@Composable
private fun StartWalkingModeIfEnabled() {
    val context=LocalContext.current
    LaunchedEffect(Unit) {
        if (WalkingPreferences(context).enabled.first()) WalkingServiceController.start(context)
    }
}

@Composable
private fun LoginScreen(onGoogle: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(FrasseCharcoal).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,verticalArrangement = Arrangement.Center
    ) {
        Text("🐾",fontSize=68.sp); Spacer(Modifier.height(20.dp))
        Text(stringResource(R.string.login_title),fontSize=30.sp,fontWeight=FontWeight.Bold,color=FrasseGold)
        Spacer(Modifier.height(10.dp)); Text(stringResource(R.string.login_subtitle),color=FrasseCream)
        Spacer(Modifier.height(34.dp))
        Button(
            onClick=onGoogle,modifier=Modifier.fillMaxWidth().height(54.dp),
            colors=ButtonDefaults.buttonColors(containerColor=FrasseTeal),shape=RoundedCornerShape(8.dp)
        ) { Text(stringResource(R.string.login_google),fontWeight=FontWeight.Bold) }
        Spacer(Modifier.height(12.dp)); Text(stringResource(R.string.login_required),fontSize=12.sp,color=FrasseCream.copy(alpha=.7f))
    }
}

@Composable
private fun NameScreen(onSubmit: (String) -> Unit) {
    var name by remember { mutableStateOf("") }
    val normalized = GameNameRules.normalize(name)
    val valid = GameNameRules.isValidPlayerName(name)
    Column(
        Modifier.fillMaxSize().background(FrasseCharcoal).padding(28.dp),
        verticalArrangement=Arrangement.Center
    ) {
        Text(stringResource(R.string.profile_name_title),fontSize=27.sp,fontWeight=FontWeight.Bold,color=FrasseGold)
        Spacer(Modifier.height(10.dp)); Text(stringResource(R.string.profile_name_help),color=FrasseCream)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value=name,onValueChange={ if (it.length<=24) name=it },singleLine=true,
            label={ Text(stringResource(R.string.profile_name_label)) },
            keyboardOptions=KeyboardOptions(capitalization=KeyboardCapitalization.Words),
            modifier=Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(18.dp))
        Button(
            onClick={ onSubmit(normalized) },enabled=valid,
            modifier=Modifier.fillMaxWidth().height(52.dp),
            colors=ButtonDefaults.buttonColors(containerColor=FrasseTeal)
        ) { Text(stringResource(R.string.profile_name_continue),fontWeight=FontWeight.Bold) }
    }
}

@Composable
private fun LoadingScreen() = Box(
    Modifier.fillMaxSize().background(FrasseCharcoal),contentAlignment=Alignment.Center
) { CircularProgressIndicator(color=FrasseGold) }

@Composable
private fun MessageScreen(title: String,body: String,buttonText: String?=null,onButton: (() -> Unit)?=null) {
    Column(
        Modifier.fillMaxSize().background(FrasseCharcoal).padding(30.dp),
        horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center
    ) {
        Text(title,fontSize=25.sp,fontWeight=FontWeight.Bold,color=FrasseGold)
        Spacer(Modifier.height(12.dp)); Text(body,color=FrasseCream)
        if (buttonText!=null && onButton!=null) {
            Spacer(Modifier.height(24.dp)); Button(onClick=onButton) { Text(buttonText) }
        }
    }
}
