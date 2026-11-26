package com.kyant.backdrop.catalog.utils

import kotlinx.coroutines.android.awaitFrame as androidAwaitFrame

// Android-only specialization of the original expect/actual wrapper.
suspend fun awaitFrame() { androidAwaitFrame() }
