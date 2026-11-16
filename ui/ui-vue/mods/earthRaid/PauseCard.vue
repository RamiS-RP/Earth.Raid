<template>
  <!-- La tarjeta de la pestaña Mods del menú de pausa: un botón al menú -->
  <div class="er-card">
    <h3>Raid.Earth</h3>
    <p class="muted">{{ t("sub") }}</p>
    <BngButton :accent="ACCENTS.main" @click="open">Raid.Earth</BngButton>
    <p class="muted key">Ctrl+Shift+G</p>
  </div>
</template>

<script setup>
import { BngButton, ACCENTS } from "@/common/components/base"
import { call, t } from "./store.js"

function open() { call("uiOpen") }
</script>

<style scoped lang="scss">
.er-card { display: flex; flex-direction: column; align-items: flex-start; gap: 10px; padding: 12px; }
h3 { margin: 0; font-size: 18px; }
.muted { margin: 0; color: #a9a294; }
.key { font-size: 13px; }
</style>
