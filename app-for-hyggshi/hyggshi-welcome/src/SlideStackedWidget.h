#pragma once
#include <QStackedWidget>

class SlideStackedWidget : public QStackedWidget {
  Q_OBJECT
 public:
  explicit SlideStackedWidget(QWidget *parent = nullptr);
  void slideToIndex(int index);
  bool isAnimating() const { return m_animating; }
  void setReducedMotion(bool enabled) { m_reducedMotion = enabled; }

 signals:
  void animationFinished();

 private:
  bool m_animating = false;
  bool m_reducedMotion = false;
  int m_durationMs = 380;
};
