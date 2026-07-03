// Klistra in din Firebase-webbkonfiguration här (Firebase Console →
// Project settings → Your apps → Web app → SDK setup and configuration).
//
// Detta är samma projekt som mobilappen använder, så webbspelare hamnar i
// samma spelrum. Firebase-webbnycklar är INTE hemliga (de är avsedda att ligga
// i klienten) — säkerheten ligger i databasreglerna, inte i nyckeln.
export const firebaseConfig = {
  apiKey: "DIN_API_KEY",
  authDomain: "DITT_PROJEKT.firebaseapp.com",
  databaseURL: "https://DITT_PROJEKT-default-rtdb.firebaseio.com",
  projectId: "DITT_PROJEKT",
  appId: "DITT_APP_ID",
};
