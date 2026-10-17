#include <QApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFile>
#include <QLabel>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setDesktopFileName("org.omarchy.terminal");
    QWidget parent;
    parent.setWindowTitle("Top-level float: org.omarchy.terminal (875x600 request)");
    parent.resize(875, 600);
    auto *layout = new QVBoxLayout(&parent);
    layout->addWidget(new QLabel("Top-level desktop float fixture\nDialog must remain on this screen"));
    parent.show();
    if (argc < 2) return app.exec();
    QTimer::singleShot(300, [&] {
        auto *dialog = new QDialog(&parent);
        dialog->setWindowTitle("Qt child dialog");
        dialog->setModal(true);
        auto *box = new QVBoxLayout(dialog);
        box->addWidget(new QLabel("Qt parent + modal\nEscape dismisses this child only"));
        auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok, dialog);
        box->addWidget(buttons);
        QObject::connect(buttons, &QDialogButtonBox::accepted, dialog, &QDialog::accept);
        QObject::connect(dialog, &QDialog::finished, [&app](int) {
            QFile out(qEnvironmentVariable("QA_RESULT")); if (out.open(QIODevice::WriteOnly)) out.write("closed");
            app.quit();
        });
        dialog->resize(420, 260);
        dialog->show();
    });
    return app.exec();
}
