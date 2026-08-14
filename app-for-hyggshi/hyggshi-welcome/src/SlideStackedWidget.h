#pragma once
#include <QStackedWidget>

// QStackedWidget có animation trượt ngang khi chuyển trang bằng slideToIndex().
// forward=true => trang mới trượt vào từ bên phải (Next),
// forward=false => trang mới trượt vào từ bên trái (Back).
class SlideStackedWidget : public QStackedWidget {
  Q_OBJECT
 public:
  explicit SlideStackedWidget(QWidget *parent = nullptr);
  void slideToIndex(int index);
  bool isAnimating() const { return m_animating; }

 signals:
  void animationFinished();

 private:
  bool m_animating = false;
  int m_durationMs = 380;
};
