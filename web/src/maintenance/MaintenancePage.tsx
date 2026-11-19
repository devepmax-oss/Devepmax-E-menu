export default function MaintenancePage() {
  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "24px",
        background: "#111111",
        color: "#ffffff",
        textAlign: "center",
      }}
    >
      <div>
        <div style={{ fontSize: "70px" }}>🍽️</div>

        <h1 style={{ fontSize: "36px", marginTop: "20px" }}>
          Estamos realizando mejoras
        </h1>

        <p style={{ fontSize: "18px", marginTop: "15px" }}>
          Go Picadera estará disponible nuevamente muy pronto.
        </p>

        <p style={{ marginTop: "10px" }}>
          Gracias por tu paciencia.
        </p>
      </div>
    </main>
  );
}